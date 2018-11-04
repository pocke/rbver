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

def ruby_versions
  RUBY_VERSION_CACHE.fetch do
    res = Net::HTTP.get(URI.parse('http://ftp.ruby-lang.org/?list-type=2&delimiter=/&prefix=pub/ruby/'))
    doc = REXML::Document.new(res)
    REXML::XPath.match(doc, '/ListBucketResult/Contents/Key')
      .map(&:text)
      .select{|f| f.start_with?('pub/ruby/ruby-') && f =~ /\.zip/}
      .map{|f| f[%r!^pub/ruby/ruby-(.+)\.zip$!, 1]}
      .reject{|v| v.end_with?('-stable')}
      .group_by{|v| ruby_version_group(v)}
      .map {|k, v| [k, v.sort_by{|x| Gem::Version.new(x)}]}
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
