class RecordsController < ApplicationController

  require_role [ "admin", "owner" ], :unless => "token_user?"

  before_filter :load_domain
  before_filter :load_record, :except => [ :create ]
  before_filter :restrict_token_movements, :except => [:create, :update, :destroy]

  def create
    @record = @domain.send( "#{params[:record][:type].downcase}_records".to_sym ).new( params[:record] )

    if current_token && !current_token.allow_new_records? &&
        !current_token.can_add?( @record )
      render :text => t(:message_token_not_authorized), :status => 403
      return
    end

    if @record.save
      # Give the token the right to undo what it just did
      if current_token
        current_token.can_change @record
        current_token.remove_records = true
        current_token.save
      end
      
      #add munin entry
      if /^A$/i =~ @record.type.to_s && MUNIN.available then
        add_munin_node
      end

    end

    respond_to do |wants|
      wants.js
    end
  end

  def update
    @record = @domain.records.find( params[:id] )

    if current_token && !current_token.can_change?( @record )
      render :text => t(:message_token_not_authorized), :status => 403
      return
    end

    if params[:check].blank?
      if @record.update_attributes( params[:record] ) then
      
        #update munin entry
        if /^A$/i =~ @record.type.to_s && MUNIN.available then
          update_munin_node
        end
        
      end
    end

    respond_to do |wants|
      wants.js
    end
  end

  def check
    @record = @domain.records.find( params[:id] )

    if current_token && !current_token.can_change?( @record )
      render :text => t(:message_token_not_authorized), :status => 403
      return
    end

    respond_to do |wants|
      wants.js
    end
  end

  def destroy
    if current_token && !current_token.can_remove?( @record )
      render :text => t(:message_token_not_authorized), :status => 403
      return
    end

    if @record.destroy then
    
      #delete munin entry
      if /^A$/i =~ @record.type.to_s && MUNIN.available then
        delete_munin_node
      end
      
    end

    respond_to do |format|
      format.html { redirect_to domain_path( @domain ) }
      format.xml { head :ok }
    end
  end

  # Non-CRUD methods
  def update_soa
    if current_token
      render :text => t(:message_token_not_authorized), :status => 403
      return
    end

    @domain.soa_record.update_attributes( params[:soa] )
    if @domain.soa_record.valid?
      flash.now[:info] = t(:message_record_soa_updated)
    else
      flash.now[:error] = t(:message_record_soa_not_updated)
    end

    respond_to do |wants|
      wants.js
    end
  end

  protected

  def load_domain
    @domain = Domain.find(params[:domain_id], :user => current_user)

    if current_token && @domain != current_token.domain
      render :text => t(:message_token_not_authorized), :status => 403
      return false
    end
  end

  def load_record
    @record = @domain.records.find( params[:id] )
  end

  def restrict_token_movements
    return unless current_token
    
    render :text => t(:message_token_not_authorized), :status => 403
    return false
  end
  
  private
  
  def add_munin_node
      m_node_file_path = MUNIN.node_config_path+@domain.name
      if !File.exist?(m_node_file_path) then
        m_node_file = open(m_node_file_path, "w")
        if m_node_file
          m_node_file.write("#domain : ["+@domain.name+"]\n#created : ["+@domain.created_at.to_s+"]\n")
          m_node_file.close
        end
      end
      
      m_node_file = open(m_node_file_path, "r+")
      if m_node_file
      
        #just add to node configuration
        m_node_file.seek(0, IO::SEEK_END)
        entry = sprintf(MUNIN.node_config_format,@domain.name,@record.name,@record.id,@record.content) 
        m_node_file.write(entry)
        m_node_file.close
        
      end
      
  end
  
  def update_munin_node
  
    m_node_file_path = MUNIN.node_config_path+@domain.name
    
    hash_config = parse_munin_config(m_node_file_path)
    
    #update configuration
    if hash_config[@domain.name+';'+@record.name+';'+@record.id.to_s] then
      hash_config[@domain.name+';'+@record.name+';'+@record.id.to_s]['address'] = @record.content
    else
      hash_config[@domain.name+';'+@record.name+';'+@record.id.to_s]={'address'=>@record.content,'use_node_name'=>true}
    end
      
    save_munin_config(m_node_file_path,hash_config)
      
  end
  
  def delete_munin_node
  
    m_node_file_path = MUNIN.node_config_path+@domain.name
    
    hash_config = parse_munin_config(m_node_file_path)
    
    #delete configuration
    hash_config.delete(@domain.name+';'+@record.name+';'+@record.id.to_s)
    
    save_munin_config(m_node_file_path,hash_config)

  end

  def parse_munin_config(m_node_file_path)
      
    hash_config = Hash::new
  
    m_node_file = open(m_node_file_path, "r")
    if m_node_file
      
      #parse node configuration and translate to hashed array
      node_name = nil
      while line = m_node_file.gets
        if /^\[([-_;a-zA-Z0-9\.]+)\]$/ =~ line then
          node_name = $1  
          hash_config[node_name] = Hash::new
        elsif node_name && /address\s+([-_a-zA-Z0-9\.]+)/ =~ line then
          hash_config[node_name]["address"] = $1 
        elsif node_name && /use_node_name\s+(true|false)/ =~ line then
          hash_config[node_name]["use_node_name"] = $1 
        end
      end
      
      m_node_file.close
    end
    
    return hash_config
       
  end
  
  def save_munin_config(m_node_file_path,hash_config)
      
    #over write configuration file 
    if m_node_file = open(m_node_file_path, "w")

      #m_node_file.rewind
      m_node_file.write("#domain : ["+@domain.name+"]\n#created : ["+@domain.created_at.to_s+"]\n")
      hash_config.each_pair {|key, value| 
         m_node_file.puts "["+key.to_s+"]"
         value.each_pair {|k, v| 
          m_node_file.puts "\t" + k.to_s + " " + v.to_s
          }
       }
      m_node_file.close
    
    end

  end
  
end
