require 'sinatra'
require 'rexml/document'
require 'net/http'
require 'json'
require 'pp'

class CacheStore
  Expire = 5 * 60 # 5 min
  None = Object.new

  def initialize
    @cache = None
    @cached_time = nil
  end

  def fetch(&block)
    return @cache if cache_available?
    block.call.tap do |v|
      @cache = v
      @cached_time = Time.now.to_i
    end
  end

  private

  def cache_available?
    @cache != None && !expired?
  end

  def expired?
    @cached_time + Expire > Time.now.to_i
  end
end

RUBY_VERSION_CACHE = CacheStore.new

# Gem::Version treats -pXXX as preview version.
# This class treats -pXXX as patch version.
class RubyVersionCompare
  include Comparable

  PATCH_REGEXP = /-p(\d+)$/

  def initialize(version_str)
    if patch = version_str[PATCH_REGEXP, 1]
      version_str = version_str.sub(PATCH_REGEXP, ".#{patch}")
    end
    @gem_version = Gem::Version.new(version_str)
  end

  def <=>(right)
    self.gem_version <=> right.gem_version
  end

  protected

  attr_reader :gem_version
end
# testing
raise unless RubyVersionCompare.new('2.0.0-p0') > RubyVersionCompare.new('2.0.0-rc2')
raise unless RubyVersionCompare.new('2.0.0-p0') > RubyVersionCompare.new('1.9.3-p551')
raise unless RubyVersionCompare.new('2.1.0-rc1') > RubyVersionCompare.new('2.0.0-p648')
raise unless RubyVersionCompare.new('2.1.0-p648') > RubyVersionCompare.new('2.0.0-p247')

def ruby_version_group(v)
  s = v.split('.')
  if s[0] == '1'
    return s.join('.')[/^(.+)-p/, 1]
  end
  return s[0..1].join('.')
end

def api_url_for(prefix)
  "http://ftp.ruby-lang.org/?list-type=2&delimiter=/&prefix=#{prefix}"
end

def get(uri)
  res = Net::HTTP.get(URI.parse(uri))
  REXML::Document.new(res)
end

def ruby_versions
  RUBY_VERSION_CACHE.fetch do
    doc = get(api_url_for('pub/ruby/'))
    REXML::XPath.match(doc, '/ListBucketResult/CommonPrefixes/Prefix')
      .map(&:text)
      .grep(%r!^pub/ruby/\d+\.\d+[a-d]?/$!)
      .select{|prefix| Gem::Version.new(prefix.split('/').last) >= Gem::Version.new('1.8')}
      .map{|prefix| [prefix, get(api_url_for(prefix))]}
      .map{|prefix, d|
        versions = REXML::XPath.match(d, '/ListBucketResult/Contents/Key')
          .map(&:text)
          .select{|f| f.start_with?(%r!pub/ruby/[^/]+/ruby-!) && f =~ /\.zip/}
          .map{|f| f[%r!^pub/ruby/[^/]+/ruby-(.+)\.zip$!, 1]}
          .reject{|v| v.end_with?('-stable')}
        [prefix.split('/').last, versions]
      }
      .map {|k, v| [k, v.sort_by{|x| RubyVersionCompare.new(x)}.reverse]}
      .reverse
      .to_h
  end
end

get '/' do
  files = ruby_versions

  content = +'<h1>Ruby Versions</h1>'
  content << files.map do |k, versions|
    <<~HTML
      <section>
        <h2>#{k}</h2>
        <ul>
          #{versions.map do|v| 
            "<li>#{v}</li>"
          end.join("\n")}
        </ul>
      </section>
    HTML
  end.join("\n")
  content << '<hr /><p>Source code is <a href="https://github.com/pocke/rbver" target="_blank">here</a></p>'
  content
end
