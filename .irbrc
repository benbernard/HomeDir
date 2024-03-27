require "awesome_print"
AwesomePrint.irb!



### BEGIN--Carrot console helpers. (Updated: Wed Mar 27 07:16:41 PDT 2024. [Script Version 1.3.27])
if ENV["CARROT_DIR"]
  helpers_dir = File.join(ENV["CARROT_DIR"], "setup", "ruby_console_helpers")
  Dir[File.join(helpers_dir, "*.rb")].each do |file|
    require file
  end
end
### END--Carrot console helpers.
