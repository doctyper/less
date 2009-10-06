$:.unshift File.dirname(__FILE__)

require 'engine/nodes'

begin
  require 'engine/parser'
rescue LoadError
  Treetop.load File.join(LESS_GRAMMAR, 'common.tt')
  Treetop.load File.join(LESS_GRAMMAR, 'entity.tt')
  Treetop.load File.join(LESS_GRAMMAR, 'less.tt')
end

module Less
  class Engine
    attr_reader :css, :less
    
    def initialize obj, options = {}
      @less = if obj.is_a? File
        @path = File.dirname File.expand_path(obj.path)
        obj.read
      elsif obj.is_a? String
        obj.dup
      else
        raise ArgumentError, "argument must be an instance of File or String!"
      end
      
      @options = options
      @parser = StyleSheetParser.new
    end
    
    def pretty?()   @options[:pretty]   end
    
    def parse build = true, env = Node::Element.new
      root = @parser.parse(self.prepare)
      
      return root unless build
      
      if root
        @tree = root.build env.tap {|e| e.file = @path }
      else
        raise SyntaxError, @parser.failure_message(@options[:color])
      end

      @tree
    end
    alias :to_tree :parse
    
    def to_css
      @css =  if pretty?
        prettify self.parse.group.to_css
      else 
        self.parse.group.to_css
      end
    end
    
    def prepare
      @less.gsub(/\r\n/, "\n").gsub(/\t/, '  ')
    end
    
    def prettify css
      # Replaces soft tabs with hard tabs
      # One line per CSS rule
      # Inserts a line break between selector groups
      css.gsub(/^  /, "\t").gsub(/\{ ([a-zA-Z\_\*\-])/, "{\n\t\\1").gsub(/(\;) \}$/, "\\1\n}").gsub(/^\}$/, "}\n")
    end
  end
end