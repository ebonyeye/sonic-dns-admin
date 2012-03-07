class AddSatusColumnToRecords < ActiveRecord::Migration
  def self.up
    add_column :records, :status, :string , :limit => 20 , :default=>'normal'
  end

  def self.down
    remove_column :records, :status
  end
end
