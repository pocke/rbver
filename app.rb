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
      .map {|k, v| [k, v.sort_by{|x| Gem::Version.new(x)}.reverse]}
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
