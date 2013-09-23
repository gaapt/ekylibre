module Nomen

  # An item of a nomenclature is the core data.
  class Item
    attr_reader :nomenclature, :name, :attributes, :children, :parent

    # New item
    def initialize(nomenclature, element, options = {})
      @nomenclature = nomenclature
      @name = element.attr("name")
      @parent = options[:parent]
      @attributes = element.attributes.inject(HashWithIndifferentAccess.new) do |h, pair|
        h[pair[0]] = cast_attribute(pair[0], pair[1].to_s)
        h
      end
    end

    # Returns children recursively by default
    def children(recursively = true)
      @children ||= nomenclature.items.values.select do |item|
        (item.parent == self)
      end
      if recursively
        return @children + @children.map(&:children).flatten
      end
      return @children
    end

    # Returns direct parents from the closest to the farest
    def parents
      return (self.parent.nil? ? [] : [self.parent] + self.parent.parents)
    end

    def self_and_children
      [self] + self.children
    end

    def self_and_parents
      [self] + self.parents
    end

    # Return human name of item
    def human_name
      "nomenclatures.#{nomenclature.name}.items.#{name}".t(:default => ["items.#{name}".to_sym, "enumerize.#{nomenclature.name}.#{name}".to_sym, "labels.#{name}".to_sym, name.humanize])
    end
    alias :humanize :human_name


    def inspect
      "#{@nomenclature.name}-#{@name}"
    end

    # Returns Attribute descriptor
    def method_missing(method_name)
      return super unless attribute = @nomenclature.attributes[method_name]
      value = @attributes[method_name]
      if value.nil? and attribute.fallbacks
        for fallback in attribute.fallbacks
          value ||= @attributes[fallback]
          break if value
        end
      end
      if attribute.default
        value ||= cast_attribute(method_name, attribute.default)
      end
      return value
    end

    private

    def cast_attribute(name, value)
      value = value.to_s
      if attribute = @nomenclature.attributes[name]
        if attribute.type == :choice
          raise InvalidAttribute.new("An attribute of choice type cannot contain commas") if value =~ /\,/
          value = value.strip.to_sym
        elsif attribute.type == :list
          value = value.strip.split(/[\,\s]+/).map(&:to_sym)
        elsif attribute.type == :boolean
          value = (value == "true" ? true : value == "false" ? false : nil)
        elsif attribute.type == :decimal
          value = value.to_d
        elsif attribute.type == :integer
          value = value.to_i
        end
      elsif name.to_s != "name" # the only system name
        raise ArgumentError.new("Undefined attribute #{name} in #{@nomenclature.name}")
      end
      return value
    end

  end


end