module Less
  module Node
    #
    # Element
    #
    # div {...}
    #
    # TODO: Look into making @rules its own hash-like class
    # TODO: Look into whether selector should be child by default
    #
    class Element
      include Enumerable
      include Entity

      attr_accessor :rules, :selector, :file,
                    :set,   :imported, :name     

      def initialize name = "", selector = ''
        @name = name
        @set, @imported = [], []
        @rules = [] # Holds all the nodes under this element's hierarchy
        @selector = Selector[selector.strip].new  # descendant | child | adjacent
      end

      def class?;     name =~ /^\./ end
      def id?;        name =~ /^#/  end
      def universal?; name == '*'   end

      def tag?
        not id? || class? || universal?
      end

      # Top-most node?
      def root?
        parent.nil?
      end

      def empty?
        @rules.empty?
      end

      def leaf?
        elements.empty?
      end

      # Group similar rulesets together
      # This is horrible, horrible code,
      # but it'll have to do until I find
      # a proper way to do it.
      def group
        matched = false
        stack, result = elements.dup, []
        return self unless elements.size > 1

        elements.each do
          e = stack.first
          result << e unless matched

          matched = stack[1..-1].each do |ee|
            if e.equiv? ee and e.elements.size == 0
              self[e].set << ee
              stack.shift
            else
              stack.shift
              break false
            end
          end if stack.size > 1
        end
        @rules -= (elements - result)
        self
      end

      #
      # Accessors for the different nodes in @rules
      #
      def identifiers; @rules.select {|r| r.kind_of?     Property } end
      def properties;  @rules.select {|r| r.instance_of? Property } end
      def variables;   @rules.select {|r| r.instance_of? Variable } end
      def elements;    @rules.select {|r| r.kind_of?     Element  } end
      def mixins;      @rules.select {|r| r.instance_of? Mixin    } end
      def parameters;  []                                           end
      def elements_and_comments; @rules.select {|r| (r.kind_of? Element) || (r.instance_of? Comment) } end

      # Select a child element
      # TODO: Implement full selector syntax & merge with descend()
      def [] key
        case key
          when Entity
            @rules.find {|i| i.eql? key }
          when String
            @rules.find {|i| i.to_s == key }
          else raise ArgumentError
        end
      end

      def == other
        name == other.name
      end

      def eql? other
        super and self.equiv? other
      end

      def equiv? other
        rules.size == other.rules.size and
        !rules.zip(other.rules).map do |a, b|
          a.to_css == b.to_css
        end.include?(false)
      end

      # Same as above, except with a specific selector
      # TODO: clean this up or implement it differently
      def descend selector, element
        if selector.is_a? Child
          s = self[element.name].selector
          self[element.name] if s.is_a? Child or s.is_a? Descendant
        elsif selector.is_a? Descendant
          self[element.name]
        else
          self[element.name] if self[element.name].selector.class == selector.class
        end
      end
      
      def mix arr = []
        @rules += arr.map do |r|
          r.copy.tap {|i| i.parent = self }
        end
      end
      
      #
      # Add an arbitrary node to this element
      #
      def << obj
        if obj.kind_of? Node::Entity
          obj.parent = self
          @rules << obj
        else
          raise ArgumentError, "argument can't be a #{obj.class}"
        end
      end

      def last;  elements.last  end
      def first; elements.first end
      def to_s; root?? '*' : name end

      #
      # Entry point for the css conversion
      #
      def to_css path = [], minify = true
        path << @selector.to_css << name unless root?

        content = properties.map do |i|
          ' ' * 2 + i.to_css
        end.compact.reject(&:empty?) * "\n"

        content = content.include?("\n") ?
          "\n#{content}\n" : " #{content.strip} "
        ruleset = !content.strip.empty??
          "#{[path.reject(&:empty?).join.strip,
          *@set.map(&:name)].uniq * ', '} {#{content}}\n" : ""

        # css = ruleset + elements.map do |i|
        #   i.to_css(path)
        # end.reject(&:empty?).join
        if root? && !minify
          css = ruleset + elements_and_comments.map do |i|
            begin
              i.to_css(path)
            rescue ArgumentError
              i.to_css
            end
          end.reject(&:empty?).join          
        else 
          css = ruleset + elements.map do |i|
            i.to_css(path)
          end.reject(&:empty?).join          
        end
        
        path.pop; path.pop
        css
      end

      #
      # Find the nearest node in the hierarchy or raise a NameError
      #
      def nearest ident, type = nil
        ary = type || ident =~ /^[.#]/ ? :elements : :variables
        path.map do |node|
          node.send(ary).find {|i| i.to_s == ident }
        end.compact.first.tap do |result|
          raise VariableNameError, ident unless result
        end
      end

      #
      # Traverse the whole tree, returning each leaf (recursive)
      #
      def each path = [], &blk
        elements.each do |element|
          path << element
          yield element, path if element.leaf?
          element.each path, &blk
          path.pop
        end
        self
      end

      def inspect depth = 0
        indent = lambda {|i| '.  ' * i }
        put    = lambda {|ary| ary.map {|i| indent[ depth + 1 ] + i.inspect } * "\n"}

        (root?? "\n" : "") + [
          indent[ depth ] + self.to_s,
          put[ variables ],
          put[ properties ],
          elements.map {|i| i.inspect( depth + 1 ) } * "\n"
        ].reject(&:empty?).join("\n") + "\n" + indent[ depth ]
      end
    end
    
    class Mixin < Element
      attr_accessor :params
      
      def initialize name, params = []
        super name
        @params = params.each do |param|
          param.parent = self
        end
      end
      
      def variables
        @params + super
      end
      
      def pass args, parent
        params.zip(args).map do |a, b|
          b ? Node::Variable.new(a.to_s, Expression.new([b])) : a
        end + identifiers + elements
      end
      
      def parameters
        @params
      end
      
      def to_s
        '.' + name
      end
      
      def to_css *args
        ""
      end
    end
  end
end