class Munin < ActiveRecord::Migration
  def self.up
    add_column :records, :status, :string
  end

  def self.down
    remove_column :records, :status
  end
end
