require 'aws-sdk'

class Store
  attr_reader :s3

  def initialize
    @s3 = AWS::S3.new(
      access_key_id: ENV['AWS_ID'],
      secret_access_key: ENV['AWS_SECRET']
    )
  end

  def namespace(name)
    bucket = s3.buckets[name]
    bucket = s3.buckets.create(name) unless bucket.exists?
    Namespace.new(bucket)
  end
end

class Namespace
  attr_reader :bucket

  def initialize(bucket)
    @bucket = bucket
  end

  def name
    bucket.name
  end

  def write(name, content)
    bucket.objects[name].write(content, acl: :public_read)
  end

  def website_configuration=(site_config)
    bucket.website_configuration = site_config.config
  end
end

class Site
  attr_reader :base_site, :www_site

  def initialize(name, service)
    site = "#{name}.com"
    @base_site = service.namespace(site)
    @www_site = service.namespace("www.#{site}")
  end

  def configure_website
    base_site.website_configuration = SiteConfiguration.new
    www_site.website_configuration = SiteConfiguration.new(redirect_to: base_site)
  end

  def upload_files(files)
    files.each do |file|
      base_site.write(File.basename(file), file.read)
    end
  end
end

class SiteConfiguration
  attr_reader :config

  def initialize(options={})
    @options = options
    @config = AWS::S3::WebsiteConfiguration.new(aws_options)
  end

  private

  attr_reader :options

  def aws_options
    if options[:redirect_to]
      aws_options = {
        redirect_all_requests_to: {
          host_name: options[:redirect_to].name
        }
      }
    end
    aws_options || {}
  end
end

class Deploy
  BUILD = 'src/**/*'

  attr_reader :site, :s3

  def initialize(site)
    @s3 = Store.new
    @site = Site.new(site, s3)
  end

  def run
    site.configure_website
    files = Dir[BUILD].map { |filename| File.open(filename) }
    site.upload_files(files)
  end
end

deploy = Deploy.new(ARGV[0])
deploy.run
