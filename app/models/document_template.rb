# = Informations
#
# == License
#
# Ekylibre - Simple agricultural ERP
# Copyright (C) 2008-2009 Brice Texier, Thibaud Merigon
# Copyright (C) 2010-2012 Brice Texier
# Copyright (C) 2012-2015 Brice Texier, David Joulin
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with this program.  If not, see http://www.gnu.org/licenses.
#
# == Table: document_templates
#
#  active       :boolean          default(FALSE), not null
#  archiving    :string           not null
#  by_default   :boolean          default(FALSE), not null
#  created_at   :datetime         not null
#  creator_id   :integer
#  formats      :string
#  id           :integer          not null, primary key
#  language     :string           not null
#  lock_version :integer          default(0), not null
#  managed      :boolean          default(FALSE), not null
#  name         :string           not null
#  nature       :string           not null
#  updated_at   :datetime         not null
#  updater_id   :integer
#

# Sources are stored in :private/reporting/:id/content.xml
class DocumentTemplate < Ekylibre::Record::Base
  enumerize :archiving, in: [:none_of_template, :first_of_template, :last_of_template, :none, :first, :last], default: :none, predicates: {prefix: true}
  enumerize :nature, in: Nomen::DocumentNatures.all, predicates: {prefix: true}
  has_many :documents, class_name: "Document", foreign_key: :template_id, dependent: :nullify, inverse_of: :template
  #[VALIDATORS[ Do not edit these lines directly. Use `rake clean:validations`.
  validates_inclusion_of :active, :by_default, :managed, in: [true, false]
  validates_presence_of :archiving, :language, :name, :nature
  #]VALIDATORS]
  validates_length_of :language, allow_nil: true, maximum: 3
  validates_length_of :archiving, :nature, allow_nil: true, maximum: 60
  validates_inclusion_of :nature, in: self.nature.values

  selects_among_all scope: :nature

  # default_scope order(:name)
  scope :of_nature, lambda { |*natures|
    natures.flatten!
    natures.compact!
    return none unless natures.respond_to?(:any?) and natures.any?
    invalids = natures.select{ |nature| Nomen::DocumentNatures[nature].nil? }
    if invalids.any?
      raise ArgumentError, "Unknown nature(s) for a DocumentTemplate: #{invalids.map(&:inspect).to_sentence}"
    end
    where(nature: natures, active: true).order(:name)
  }

  protect(on: :destroy) do
    self.documents.any?
  end

  before_validation do
    # Check that given formats are all known
    unless self.formats.empty?
      self.formats = self.formats.to_s.downcase.strip.split(/[\s\,]+/).delete_if do |f|
        !Ekylibre::Reporting.formats.include?(f)
      end.join(", ")
    end
  end

  after_save do
    # Install file after save only
    if @source
      FileUtils.mkdir_p(self.source_path.dirname)
      File.open(self.source_path, "wb") do |f|
        # Updates source to make it working
        document = Nokogiri::XML(@source) do |config|
          config.noblanks.nonet.strict
        end
        # Removes comments
        document.xpath('//comment()').remove
        # Updates template
        if document.root and document.root.namespace and document.root.namespace.href == "http://jasperreports.sourceforge.net/jasperreports"
          if template = document.root.xpath('xmlns:template').first
            logger.info "Update <template> for document template #{self.nature}"
            template.children.remove
            style_file = Ekylibre::Tenant.private_directory.join("corporate_identity", "reporting_style.xml")
            # TODO find a way to permit customization for users to restore that
            if true # unless style_file.exist?
              FileUtils.mkdir_p(style_file.dirname)
              FileUtils.cp(Rails.root.join("config", "corporate_identity", "reporting_style.xml"), style_file)
            end
            template.add_child(Nokogiri::XML::CDATA.new(document, style_file.relative_path_from(self.source_path.dirname).to_s.inspect))
          else
            logger.info "Cannot find and update <template> in document template #{self.nature}"
          end
        end
        # Writes source
        f.write(document.to_s)
      end
      # Remove .jasper file to force reloading
      Dir.glob(self.source_path.dirname.join("*.jasper")).each do |file|
        FileUtils.rm_f(file)
      end
    end
  end

  # Updates archiving methods of other templates of same nature
  after_save do
    if self.archiving.to_s =~ /\_of\_template$/
      self.class.where("nature = ? AND NOT archiving LIKE ? AND id != ?", self.nature, "%_of_template", self.id).update_all("archiving = archiving || '_of_template'")
    else
      self.class.where("nature = ? AND id != ?", self.nature, self.id).update_all(:archiving => self.archiving)
    end
  end

  # Always after protect on destroy
  after_destroy do
    if self.source_dir.exist?
      FileUtils.rm_rf(self.source_dir)
    end
  end

  # Install the source of a document template
  # with all its dependencies
  def source=(file)
    @source = file
  end

  # Returns source value
  def source
    @source
  end

  # Returns the expected dir for the source file
  def source_dir
    return self.class.sources_root.join(self.id.to_s)
  end

  # Returns the expected path for the source file
  def source_path
    return self.source_dir.join("content.xml")
  end

  # Print a document with the given datasource and return raw data
  # Store if needed by template
  # @param datasource XML representation of data used by the template
  def print(datasource, key, format = :pdf, options = {})
    # Load the report
    report = Beardley::Report.new(self.source_path, locale: "i18n.iso2".t)
    # Call it with datasource
    data = report.send("to_#{format}", datasource)
    # Archive the document according to archiving method. See #document method.
    self.document(data, key, format, options)
    # Returns only the data (without filename)
    return data
  end


  # Export a document with the given datasource and return path file
  # Store if needed by template
  # @param datasource XML representation of data used by the template
  def export(datasource, key, format = :pdf, options = {})
    # Load the report
    report = Beardley::Report.new(self.source_path, locale: "i18n.iso2".t)
    # Call it with datasource
    path = Pathname.new(report.to_file(format, datasource))
    # Archive the document according to archiving method. See #document method.
    if document = self.document(path, key, format, options)
      FileUtils.rm_rf(path)
      path = document.file.path(:original)
    end
    # Returns only the path
    return path
  end



  # Returns the list of formats of the templates
  def formats
    (self["formats"].blank? ? Ekylibre::Reporting.formats : self["formats"].strip.split(/[\s\,]+/))
  end

  def formats=(value)
    self["formats"] = (value.is_a?(Array) ? value.join(", ") : value.to_s)
  end

  # Archive the document using the given archiving method
  def document(data_or_path, key, format, options = {})
    document = nil
    return document if self.archiving_none? or self.archiving_none_of_template?

    # Gets historic of document
    documents = Document.where(nature: self.nature, key: key).where("template_id IS NOT NULL")

    # Checks if archiving is expected
    return document unless (self.archiving_first? and documents.empty?) or
      (self.archiving_first_of_template? and documents.where(template_id: self.id).empty?) or
      self.archiving.to_s =~ /^(last|all)(\_of\_template)?$/

    # Lists last documents to remove after archiving
    removables = []
    if self.archiving_last?
      removables = documents.pluck(:id)
    elsif self.archiving_last_of_template?
      removables = documents.where(template_id: self.id).pluck(:id)
    end

    # Creates document if not exist
    document = Document.create!(nature: self.nature, key: key, name: (options[:name] || tc('document_name', nature: self.nature.l, key: key)), file: File.open(data_or_path), template_id: self.id)

    # Removes useless docs
    Document.destroy removables

    return document
  end

  class << self

    # Print document with default active template for the given nature
    # Returns nil if no template found.
    def print(nature, datasource, key, format = :pdf, options = {})
      if template = self.where(:nature => nature, :by_default => true, :active => true).first
        return template.print(datasource, key, format, options)
      end
      return nil
    end
    
    # Returns the root directory for the document templates's sources
    def sources_root
      Ekylibre::Tenant.private_directory.join("reporting")
    end

    # Compute fallback chain for a given document nature
    def template_fallbacks(nature, locale)
      root = Rails.root.join("config", "locales", locale, "reporting")
      stack = []
      stack << root.join("#{nature}.xml")
      stack << root.join("#{nature}.jrxml")
      fallback = {
        sales_order: :sale,
        sales_estimate: :sale,
        sales_invoice: :sale,
        purchases_order: :purchase,
        purchases_estimate: :purchase,
        purchases_invoice: :purchase,
      }[nature.to_sym]
      if fallback
        stack << root.join("#{fallback}.xml")
        stack << root.join("#{fallback}.jrxml")
      end
      return stack
    end

    # Loads in DB all default document templates
    def load_defaults(options = {})
      locale = (options[:locale] || Preference[:language] || I18n.locale).to_s
      Ekylibre::Record::Base.transaction do
        manageds = self.where(managed: true).select(&:destroyable?)
        for nature in self.nature.values
          if source = template_fallbacks(nature, locale).detect{|p| p.exist? }
            File.open(source, "rb:UTF-8") do |f|
              unless template = self.find_by(nature: nature, managed: true)
                template = self.new(nature: nature, managed: true, active: true, by_default: false, archiving: "last")
              end
              manageds.delete(template)
              template.attributes = {source: f, language: locale}
              template.name ||= template.nature.l
              template.save!
            end
            Rails.logger.info "Load a default document template #{nature}"
          else
            Rails.logger.warn "Cannot load a default document template #{nature}: No file found at #{source}"
          end
        end
        self.destroy(manageds.map(&:id))
      end
      return true
    end

  end

end
