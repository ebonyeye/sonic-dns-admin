class DomainsController < ApplicationController

  require_role [ "admin", "owner" ], :unless => "token_user?"

  # Keep token users in line
  before_filter :restrict_token_movements, :except => :show

  before_filter :load_domain, :except => [ :index, :new, :create ]

  protected

  def load_domain
    if current_user
      @domain = Domain.find( params[:id], :user => current_user )
    else
      @domain = Domain.find( current_token.domain_id, :include => :records )
    end
  end

  def restrict_token_movements
    redirect_to domain_path( current_token.domain ) if current_token
  end

  public

  def index
    respond_to do |wants|
      wants.html do
        @domains = Domain.paginate :page => params[:page], :user => current_user, :order => 'name'
      end
      wants.xml do
        @domains = Domain.find(:all, :user => current_user, :order => 'name')
        render :xml => @domains
      end
    end
  end

  def show
    if current_user && current_user.admin?
      @users = User.active_owners
    end

    respond_to do |format|
      format.html {
        @record = @domain.records.new
      }
      format.xml { render :xml => @domain.to_xml(:include => [:records]) }
    end
  end

  def new
    @domain = Domain.new
    @zone_templates = ZoneTemplate.find( :all, :require_soa => true, :user => current_user )
  end

  def create
    @domain = Domain.new( params[:domain] )

    unless @domain.slave?
      @zone_template = ZoneTemplate.find(params[:domain][:zone_template_id]) unless params[:domain][:zone_template_id].blank?
      @zone_template ||= ZoneTemplate.find_by_name(params[:domain][:zone_template_name]) unless params[:domain][:zone_template_name].blank?

      unless @zone_template.nil?
        begin
          @domain = @zone_template.build( params[:domain][:name] )
        rescue ActiveRecord::RecordInvalid => e
          @domain.attach_errors(e)
        end
      end
    end

    @domain.user = current_user unless current_user.has_role?( 'admin' )

    respond_to do |format|
      if @domain.save
        format.html { 
          flash[:info] = t(:message_domain_created)
          redirect_to domain_path( @domain ) 
        }

        #create munin node file
        if MUNIN.available
          m_node_file_path = MUNIN.node_config_path+@domain.name
          if File.exist?(m_node_file_path) then 
            if(!FileTest.directory?(m_node_file_path)) then
              File.delete(m_node_file_path);
            end
          end
          
          m_node_file = open(m_node_file_path, "w")
          if m_node_file
            #entry = sprintf(MUNIN.node_config_format,@domain.name,'10.0.0.1') 
            m_node_file.write("#domain : ["+@domain.name+"]\n#created : ["+@domain.created_at.to_s+"]\n")
            records = @domain.records_without_soa
             records.each{|record|
                if /^A$/i =~ record.type.to_s then
                  entry = sprintf(MUNIN.node_config_format,@domain.name,record.name,record.id,record.content) 
                  m_node_file.write(entry)
                end
              }
            m_node_file.close
          end
        end
        
        format.xml { render :xml => @domain.to_xml(:include => [:records]), :status => :created, :location => domain_url( @domain ) }
      else
        format.html {
          @zone_templates = ZoneTemplate.find( :all )
          render :action => :new
        }
        format.xml { render :xml => @domain.errors, :status => :unprocessable_entity }
      end
    end
  end

  def edit
    @zone_templates = ZoneTemplate.find(:all, :require_soa => true, :user => current_user)
  end

  def update
    if @domain.update_attributes(params[:domain])
      respond_to do |wants|
        wants.html do
          flash[:info] = t(:message_domain_updated)
          redirect_to domain_path(@domain)
        end
        wants.xml { render :xml => @domain.to_xml(:include => [:records]), :location => domain_url(@domain) }
      end
    else
      respond_to do |wants|
        wants.html do
          @zone_templates = ZoneTemplate.find(:all, :require_soa => true, :user => current_user)
          render :action => "edit"
        end
        wants.xml { render :xml => @domain.errors, :status => :unprocessable_entity }
      end
    end
  end

  def destroy
    if @domain.destroy then
      
      #delete munin node file
      if MUNIN.available
        m_node_file_path = MUNIN.node_config_path+@domain.name
        if File.exist?(m_node_file_path) then 
          if(!FileTest.directory?(m_node_file_path)) then
            File.delete(m_node_file_path);
          end
        end
      end
      
    end
    
    respond_to do |format|
      format.html { redirect_to :action => 'index' }
      format.xml { render :xml => @domain.to_xml(:include => [:records]), :status => :no_content }
    end
  end

  def score
    msg = "";
    #calculate ttl with performance data
    if MUNIN.available
      
      records = @domain.records_without_soa
      records.each{|record|
        if /^A$/i =~ record.type.to_s then
#          rrd = MUNIN.database_path+@domain.name+"/"+record.name+"/"+record.id.to_s+"-load-load-g.rrd"
#          if File.exist?(rrd) then
#            cmd = "/usr/bin/rrdtool fetch " + rrd + " AVERAGE -s -15m -r 60"
#            
#            #msg+= "attempt to perform cmd #{cmd}<br>"
#            msg+= "<b>fetching rrd of #{record.name}</b><br>"
#            i = s = 0
#            IO.popen(cmd, 'r+') do |io|
#              while line = io.gets
#                if /^(\d+):.*$/ =~ line then
#                  msg+= $1+"<br>"
#                  i+=1
#                  s+=$1.to_i
#                end
#              end
#            end
#            msg+= "load avg(#{record.name}) = #{s/i}<br>"
              
              #閾値を超えたらレコード一定の粒度でTTLを決定
            perf = MUNIN.web_path+@domain.name+"/"+record.name+"/"+record.id.to_s+"/load_extended.perf"
            msg+= "<b>performance state of #{record.name}</b><br>"
            if File.exist?(perf) then
              hash_perf = Hash::new
            
              perf_file = open(perf, "r")
              if perf_file
                
                #parse node configuration and translate to hashed array
                section_name = nil
                while line = perf_file.gets
                  if /^update\=([0-9]+)$/ =~ line then
                    hash_perf['update_at'] = $1 
                    msg+= "last update at #{Time.at($1.to_i)}<br>"
                  elsif /^\[([-_a-zA-Z0-9]+)\]$/ =~ line then
                    section_name = $1  
                    hash_perf[section_name] = Hash::new
                    msg+= "[#{section_name}] <br>"
                  elsif section_name && /^([-_a-zA-Z0-9]+)\=([-_a-zA-Z0-9\.]+)$/ =~ line then
                    hash_perf[section_name][$1] = $2 
                    msg+= "#{$2}<br>"
                  elsif section_name && /^#([-_a-zA-Z0-9][-_a-zA-Z0-9\s\.]+)$/ =~ line then
                    msg+= "#{$1}<br>"
                  end
                end
                perf_file.close
              end
                          
            else
                #パフォーマンスデータが蓄積されていないため、IRR対象外 
              msg+= "There is nothing performance state yet. <br>"
            end 
              
#         else
              #パフォーマンスデータが蓄積されていないため、IRR対象外 
#            msg+= "rrd is not collected yet. #{record.name}<br>"
#          end

 
        end
       }
     end
     
    respond_to do |wants|
      wants.html do
        flash[:info] = msg#t(:message_domain_scored)
        redirect_to domain_path(@domain)
      end
      wants.xml { render :xml => @domain.to_xml(:include => [:records]), :location => domain_url(@domain) }
    end
     
  end

  # Non-CRUD methods
  def update_note
    @domain.update_attribute( :notes, params[:domain][:notes] )
  end

  def change_owner
    @domain.update_attribute :user_id, params[:domain][:user_id]

    respond_to do |wants|
      wants.js
    end
  end

  # GET: list of macros to apply
  # POST: apply selected macro
  def apply_macro
    if request.get?
      @macros = Macro.find(:all, :user => current_user)

      respond_to do |format|
        format.html
        format.xml { render :xml => @macros }
      end

    else
      @macro = Macro.find( params[:macro_id], :user => current_user )
      @macro.apply_to( @domain )

      respond_to do |format|
        format.html {
          flash[:notice] = t(:message_domain_macro_applied)
          redirect_to domain_path(@domain)
        }
        format.xml { render :xml => @domain.reload.to_xml(:include => [:records]), :status => :accepted, :location => domain_path(@domain) }
      end

    end

  end

end
