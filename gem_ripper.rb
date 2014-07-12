require_relative 'codesearcher.rb'

GEMS = `gem environment`.split("\n").grep(/INSTA/).first.split(' ').last + '/gems'

puts "what pattern are you looking for?"
pattern = gets.chomp

Dir[GEMS + '/**/*.rb'].each do |file|
  CodeSearcher.render(pattern, file)
end
