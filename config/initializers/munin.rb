# Be sure to restart your server when you modify this file.

# These settings change the behavior of Rails 2 apps and will be defaults
# for Rails 3. You can remove this initializer when Rails 3 is released.

# URL PREFIX MUNIN
if !defined?(MUNIN)
  site_def = Struct.new(:available,:config_path,:node_config_path,:database_path,:web_path,:url,:node_config_format)
  MUNIN =  site_def.new()
  MUNIN.available = true
  MUNIN.config_path = "/etc/munin/"
  MUNIN.node_config_path = MUNIN.config_path + "node.d/"
  MUNIN.database_path = "/var/lib/munin/database/"
  MUNIN.web_path = "/var/www/html/munin/"
  MUNIN.url = "http://localhost/munin/"
  MUNIN.node_config_format = "[%s;%s;%d]\n\taddress\s%s\n\tuse_node_name\strue\n"
end

