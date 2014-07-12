require 'ripper'

###############################################################################
# USAGE
###############################################################################
# load the code to search
# use readlines() to print source lines or read() if not
# code = File.read('code.rb')
# code = File.readlines('code.rb')
#
# define the search pattern as Ruby code
# pattern = CodeSearcher.patternize("op.on('-p port', 'set the port (4567)')")
#
# alternatively you can use any one of the symbols below to match explicitly
#
# Ripper::SCANNER_EVENT_TABLE.keys output
#
# [:CHAR, :__end__, :backref, :backtick, :comma, :comment, :const,
#  :cvar, :embdoc, :embdoc_beg, :embdoc_end, :embexpr_beg, :embexpr_end,
#  :embvar, :float, :gvar, :heredoc_beg, :heredoc_end, :ident,
#  :ignored_nl, :int, :ivar, :kw, :label, :lbrace, :lbracket, :lparen,
#  :nl, :op, :period, :qsymbols_beg, :qwords_beg, :rbrace, :rbracket,
#  :regexp_beg, :regexp_end, :rparen, :semicolon, :sp, :symbeg,
#  :symbols_beg, :tlambda, :tlambeg, :tstring_beg, :tstring_content,
#  :tstring_end, :words_beg, :words_sep]
#
# for example, pattern = CodeSearcher.patternize(":backtick")

# look for the pattern returning tuples of [match count, [firstline, lastline]]
# results = CodeSearcher.find(pattern, code)
#
# optionally render those results
# CodeSearcher.render code, pattern, results
#
###############################################################################

module CodeSearcher

  extend self

  ###############################################################################
  # Token
  # simple data type used to represent a collection of related attributes used
  # during the search process.  these attributes may change over time as the
  # program evolves
  #
  # so needed something like OpenStruct but chose not to require 'ostruct'
  #
  ###############################################################################

  class Token
    def initialize(args)
      args.each do |attribute, value|
        instance_variable_set("@#{attribute}", value)
        self.class.class_eval { attr_reader attribute.to_sym}
      end
    end
  end

  ###############################################################################
  # validate / expand
  ###############################################################################
  #
  # these methods expect a 'pattern' in the form of: 'const|sp|op(<)|sp|const|'
  # where the pattern represents a list of tokens and an optional clarifier
  # representing the structure of a code snippet
  #
  # validate() ensures that only the following tokens are supported:
  # expand() translates the simplified string into a more useful data structure
  #
  # (supported tokens are basically keys of Ripper::SCANNER_EVENT_TABLE)
  #
  # [:CHAR, :__end__, :backref, :backtick, :comma, :comment, :const,
  #  :cvar, :embdoc, :embdoc_beg, :embdoc_end, :embexpr_beg, :embexpr_end,
  #  :embvar, :float, :gvar, :heredoc_beg, :heredoc_end, :ident,
  #  :ignored_nl, :int, :ivar, :kw, :label, :lbrace, :lbracket, :lparen,
  #  :nl, :op, :period, :qsymbols_beg, :qwords_beg, :rbrace, :rbracket,
  #  :regexp_beg, :regexp_end, :rparen, :semicolon, :sp, :symbeg,
  #  :symbols_beg, :tlambda, :tlambeg, :tstring_beg, :tstring_content,
  #  :tstring_end, :words_beg, :words_sep]

  # input: 'const|op(<)|const|'
  # output: 0 or ArgumentError
  def valid(pattern)
    expand(pattern).map(&:symbol).each do |token|
      unless  Ripper::SCANNER_EVENT_TABLE.keys.include? token
        raise ArgumentError, "unsupported token [#{token}]!"
      end
    end
    pattern
  end

  # input: 'const|sp|op(<)|sp|const|'
  # output: [[:const], [:sp], [:op, '(<)'], [:sp], [:const]]
  def expand(pattern)
    pattern << '|' unless pattern[-1][/\|/]
    pairs = pattern.scan(/([a-z_]*)(\(.\))?\|/)
                   .map{|el| [el.first.to_sym, el.last]}
                  # .map(&:compact)
    pairs.map{|pair| Token.new(symbol: pair.first, detail: pair.last) }
  end


  ###############################################################################
  # tokenize / patternize
  #
  # these methods prepare snippets of code for analysis including code we're looking
  # through and the code that we're looking for.
  #
  ###############################################################################

  # input:  snippet of code as text
  # output: simplified results of Ripper.lex() as [line, token]
  def tokenize(snippet, mode = :lex)
    case mode
    when :lex
      Ripper.lex(snippet).map{|a,b,_| [a.first, b.to_s.gsub(/on_/,'').to_sym]}
    when :sexp
      raise ArgumentError, "Ripper.sexp not implemented yet."
    else
      raise ArgumentError, "unsupported tokenization: [#{mode}]."
    end
  end

  # input:  snippet of code as text
  # output: pattern for use with expand
  def prepare(snippet)
    return snippet if snippet =~ /^:\S*/
    tokenize(snippet).map(&:last) * '|' + '|'
  end

  ###############################################################################
  # render
  ###############################################################################

  def render(pattern, file)
    output = "-"*20
    find(pattern, file).each do |count, (first, last)|
      output += "\n#{count} #{count == 1 ? 'match' : 'matches'} "
      output += "found on line #{first} of #{file}:\n"
      output += "\t#{File.readlines(file)[first-1..last-1].first.strip}\n\n"
      puts output
      output = ''
    end
  end

  ###############################################################################
  # find
  ###############################################################################

  # input:
  #   pattern as "valid ruby code"
  #   snippet as String or [String] with some chunk of Ruby code
  #   format as nil, :counted or :pairs
  # output: array of [start, end] pairs where pattern was found, otherwise []
  def find(pattern, file, format = :counted)
    line_pairs = []
    search_pattern = expand(valid(prepare(pattern)))
    tokenized_file = tokenize(File.read(file))
    idx, first, last = 0, 0, 0

    tokenized_file.each do |line, token|

      if idx == search_pattern.length
        line_pairs << [first, last]
        idx, first, last = 0, 0, 0
        next
      end

      matched  = token == search_pattern[idx].symbol
      space    = search_pattern[idx] == 'sp'
      wildcard = search_pattern[idx] == '*'

      if matched || space || wildcard
        first = line if idx.zero?
        last = line
        idx += 1
      else
        idx, first, last = 0, 0, 0
      end
    end

    # return nil if line_pairs.empty?

    case format
      when :counted then return line_pairs.group_by{|el| el}.map{|k,v| [v.length, k]}
      when :pairs   then return line_pairs
      else return line_pairs
    end

  end

end

# ------------------------------------

if __FILE__ == $0

  # shorten the name of the module
  CS = CodeSearcher

  # target a specific code file
  file = 'code.rb'

  pattern = "op.on('-p port', 'set the port (default is 4567)')"
  CS.render pattern, file

  pattern = "->"
  CS.render pattern, file

  pattern = 'extend Sinatra::Delegator'
  CS.render pattern, file

  pattern = 'class Application < Base'
  CS.render pattern, file

  pattern = 'class Application < Base'
  CS.render pattern, file

end

__END__

bugs:
  - still not ignoring spaces
  - the string interpolation thing doesn't work the way you think it does (see line 205)

todo:
  - medium: add ability to constrain literal parts of a pattern, ie. `patternize(MyClass.new, strict: 'new')`
  - epic:   add github integration

done:
  - medium: generate pattern by ripping and simplifying student-entered code
  - small:  run through multiple files generating line ranges of interest

notes:
  - github source code url append with #L17-24 to highlight lines


