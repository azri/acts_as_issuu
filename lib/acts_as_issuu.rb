require 'hpricot'

module Issuu

  Configuration = "#{RAILS_ROOT}/config/issuu.yml".freeze

  # RegExp that matches AWS S3 URLs
  S3 = /^https?:\/\/s3.amazonaws.com/
  
  class IssuuConfigError < StandardError; end
  class IssuuUploadError < StandardError; end
  class IssuuDeleteError < StandardError; end
  class IssuuError < StandardError; end

  class << self

    def included(base)
      base.extend ClassMethods
    end

    def issuu_config
      raise IssuuConfigError,"#{Configuration} does not exist" unless File.file?(Configuration)
      YAML.load_file(Configuration).each_pair{|k,v| {k=>v.to_s.strip}}.symbolize_keys!
    end
   
    def upload_document doc_obj
      res = Issuu::Connect.new(issuu_config).document_upload(doc_obj.issuu_document_params)
      xml = Hpricot.XML(res.body)
      if (xml/:rsp).first.attributes["stat"] == "fail"
        error_attr = (xml/:rsp/:error).first.attributes
        if !error_attr["field"].nil?
          raise IssuuUploadError, error_attr["field"]+":"+error_attr["message"]
        end
      else
        doc_attributes = (xml/:rsp/:document).first.attributes      
        doc_obj.update_attributes({
          :issuu_docId => doc_attributes["documentId"], 
          :issuu_name => doc_attributes["name"],
          :issuu_title => doc_attributes["title"]
        })
      end
    end

    def documents_listing
      res = Issuu::Connect.new(issuu_config).document_list
      xml = Hpricot.XML(res)
      (xml/:rsp/:result/:document).map do |doc|
        attributes = doc.attributes
        {
          'documentId' => attributes["documentId"], 
          'name' => attributes["name"],
          'title' => attributes["title"]
        }
      end 
    end
  
    def delete_document doc_obj
      res = Issuu::Connect.new(issuu_config).document_delete(doc_obj.issuu_name)
      xml = Hpricot.XML(res.body)
      if (xml/:rsp).first.attributes["stat"] != "ok"
        raise IssuuDeleteError, "deletion failed"
      end
    end
  end

  module ClassMethods

    def acts_as_issuu(str)
      include InstanceMethods

      load_base_plugin(str)

      after_save :upload_doc_to_issuu
      before_destroy :delete_doc_from_issuu       
    end

    private

    def load_attachment_fu
      require 'issuu/attachment_fu'
      include Issuu::AttachmentFu::InstanceMethods
    end
    
    def load_paperclip
      require 'issuu/paperclip'
      include Issuu::Paperclip::InstanceMethods
    end
    
    def load_base_plugin(str)
      if str == 'AttachmentFu'
        load_attachment_fu
      elsif str == 'Paperclip'
        load_paperclip
      else
        raise IssuuError, "Sorry, only Attachment_fu and Paperclip are supported."
      end
    end      
  end
   
  module InstanceMethods

    def self.included(base)
      base.extend ClassMethods
    end

    def upload_doc_to_issuu
      Issuu::upload_document(self) if self.issuu_docId.nil?     
    end

    def delete_doc_from_issuu
      Issuu::delete_document(self)
    end

    # User can define NAME for the document that is uploaded to issuu
    # Value determining the URL address of the publication http://issuu.com/<username>/docs/<name>
    # The name must be 3-50 characters long. Use lowercase letters (a-z), numbers (0-9) and characters (_.-). No spaces allowed.
    # This value must be unique for the account. In case no value is specified this name will be autogenerated.


    # TITLE of the publication. If no value is specified the filename of the uploaded document will be used

    def issuu_document_params
      {
        :file_rel_path => file_path,
        :issuu_name => issuu_name,
        :issuu_title => issuu_title
      }
    end
  end
end

ActiveRecord::Base.send(:include, Issuu) if Object.const_defined?("ActiveRecord")
