module Aggeratio
  class Base

    LEVELS = [:api, :human]

    attr_reader :name, :parameters, :root, :aggregator

    def initialize(aggregator)
      @minimum_level = LEVELS.last
      @aggregator = aggregator
      @name = @aggregator.attr("name")
      @parameters = @aggregator.children[0].children.collect do |element|
        Parameter.import(element)
      end
      @root = @aggregator.children[1]
    end

    def class_name
      name.camelcase
    end

    def build
      raise NotImplementedEror.new
    end

    def build_variable(element)
      return "#{element.attr('name')} = #{value_of(element)}\n"
    end

    def properties(element = nil)
      element ||= @root
      array = []
      array << element if ["section", "cell", "property", "title"].include?(element.name)
      for child in element.children
        if child.has_attribute?('name') and not child.attr('name') =~ /^\w+(\_\w+)*$/
          raise InvalidDocument, "#{child.name} element has invalid name attribute: #{child.attr('name').to_s}"
        end
        array += self.properties(child)
      end
      return array
    end


    def parameter_initialization
      code = ""
      for parameter in parameters
        code << "#{parameter.name} = @#{parameter.name}\n"
      end
      return code
    end

    def conditionate(code, element, minimum_level = nil)
      minimum_level ||= @minimum_level || :api
      level = (element.has_attribute?('level') ? element.attr('level').strip.to_sym : @minimum_level)
      return "" if LEVELS.index(minimum_level) > LEVELS.index(level)
      if element.has_attribute?('if')
        test = element.attr('if').strip.gsub(/[\r\n\t]+/, ' ')
        code = "if (#{test})\n" + code.dig + "end\n"
      elsif element.has_attribute?('unless')
        test = element.attr('unless').strip.gsub(/[\r\n\t]+/, ' ')
        code = "unless (#{test})\n" + code.dig + "end\n"
      end
      return code
    end


    def normalize_name(name)
      name = name.attr('name') unless name.is_a?(String)
      name.to_s.strip.gsub('_', '-')
    end

    def value_of(element)
      value = (element.has_attribute?("value") ? element.attr("value") : element.has_attribute?("name") ? element.attr("name") : "inspect")
      value = element.attr("of") + "." + value if element.has_attribute?("of")
      return value
    end


    def human_value_of(*args)
      options = args.extract_options!
      element = args.shift
      tag = args.shift

      value = value_of(element)
      type = (element.has_attribute?("type") ? element.attr("type").to_s : :string).to_s.gsub('-', '_').to_sym
      code = if type == :date or type == :datetime
               "xml.text(#{value}.l) unless #{value}.nil?"
             elsif type == :measure
               "xml.text(#{value}.l) unless #{value}.nil?"
             elsif type == :url
               "xml.a(#{value}, href: #{value}) unless #{value}.blank?"
             else
               "xml.text(#{value})"
             end
      if type != :url and element.has_attribute?("of-type")
        of = element.attr("of").to_s
        of_type = element.attr("of-type").to_sym
        if of_type == :record and of.present?
          code = "if #{of}.class < Ekylibre::Record::Base\n" +
            "  xml.a(:href => \"/backend/\#{#{of}.class.table_name}/\#{#{of}.to_param}\") do\n" + code.dig(2) + "  end\n" +
            "else\n" + code.dig + "end\n"
        end
      end
      unless tag.nil?
        code = "xml.#{tag}(#{options.inspect}) do\n" + code.dig + "end\n"
      end
      return code
    end


    def human_name_of(element)
      name = element.attr('value').to_s.downcase # unless name.is_a?(String)
      name = element.attr('name') unless name.match(/^\w+$/)
      name = name.to_s.strip.gsub('-', '_')
      return "'aggregator_properties.#{name}'.t(default: [:'attributes.#{name}', :'labels.#{name}', :'activerecord.models.#{name}', #{name.to_s.humanize.inspect}])"
    end

    # Returns all default XPATH queries
    def queries(options = {})
      return @root.xpath("//node()[not(node())]").collect do |leaf|
        next if options[:strict].is_a?(FalseClass) and leaf.has_attribute?("if")
        xpath(leaf)
      end.compact
    end

    private

    def xpath(element)
      return nil if ["comment", "variable"].include?(element.name)
      name = element.name.to_s.upcase
      if ["matrix", "sections"].include?(element.name)
        name = normalize_name(element.attr("for"))
        if element.has_attribute?("name")
          name = normalize_name(element.attr("name")) + "/" + name
        end
      elsif element.has_attribute?("name")
        name = normalize_name(element.attr("name"))
      end
      prefix = (["property", "title"].include?(element.name) ? "/@" : "/")
      if element == @root
        return prefix + name
      elsif element.parent and !element.parent.is_a?(Nokogiri::XML::Document)
        return xpath(element.parent) + prefix + name rescue nil
      else
        return nil
      end
    end

  end
end
