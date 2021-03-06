module GarnetRuby
  class Environment
    LexicalScope = Struct.new(:klass, :next_scope)
    ScopeVisi = Struct.new(:method_visi, :module_func)

    attr_accessor :block, :method_entry, :method_object, :errinfo, :scope_visi
    attr_reader :lexical_scope, :locals, :previous

    def initialize(klass, next_scope, locals = {}, previous = nil, method_entry = nil)
      @lexical_scope = LexicalScope.new(klass, next_scope)
      @locals = locals
      @previous = previous
      @method_entry = method_entry
      @scope_visi = ScopeVisi.new(:public, false)
    end

    def next_scope
      lexical_scope.next_scope
    end

    def klass
      lexical_scope.klass
    end

    def method_name
      method_object&.called_id
    end

    def to_s
      "<ENV klass=#{lexical_scope.klass} next=#{lexical_scope.next_scope&.lexical_scope&.klass} locals=#{locals} prev=#{previous}>"
    end
    alias inspect to_s
  end
end
