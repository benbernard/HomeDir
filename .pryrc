

### BEGIN--Carrot console helpers. (Updated: Wed Jan  4 10:16:20 PST 2023. [Script Version 1.3.22])
if ENV["CARROT_DIR"]
  helpers_dir = File.join(ENV["CARROT_DIR"], "setup", "ruby_console_helpers")
  Dir[File.join(helpers_dir, "*.rb")].each do |file|
    require file
  end
end
### END--Carrot console helpers.
