#!/opt/third-party/bin/ruby -w

def error(msg)
  STDERR.puts "# " + msg
  exit
end

# Given a search string 's', return directories that match the
# characters of 's' with stars in between.
#
# If all characters were lowercase, assume case insensitive, otherwise do a case
# sensitive search
def match_glob(s)
  glob = '*' + s.gsub(/./, '\0*')
  args = ["./" + glob]
  args << File::FNM_CASEFOLD if s.downcase == s
  matches = Dir.glob(*args).select { |file| test(?d, file) }
  if ! matches.empty?
    matches
  else
    `find -type d -follow 2>/dev/null`.gsub(/^\.\//,'').split.delete_if {|i| File.basename(i) !~ Regexp.new(glob.gsub('*','.*'))}
  end
end

def select_target(matches)
  error "No directory match found" if matches.empty?

  if (matches.size > 1) then
    matches.each_with_index { |dir, idx| STDERR.puts "#{idx+1}: #{dir}" }

    STDERR.print "\nglob_change> "
    search_string = STDIN.gets.strip
    index = search_string.to_i

    if (index == 0) then
      STDERR.puts "glob /#{search_string}/"
      target = select_target(matches.delete_if {|i| i !~ Regexp.new(search_string.gsub(/./,'\0.*')) })
    else
      STDERR.puts "index #{index}"
      target = matches[index-1]
    end

    error "Invalid index '#{index}'" if target.nil?
  else
    target = matches[0]
  end

  target
end

# main

dir_matches = match_glob(ARGV[0] || "*")

error "No directory match found for '#{ARGV[0]}'" if dir_matches.empty?

target_dir = select_target(dir_matches)

STDERR.puts "cd => #{target_dir}"
puts "cd " + target_dir
