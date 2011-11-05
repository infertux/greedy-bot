# 0. load settings
# 1. clone/pull repos
# 2. create new branch 'cleanup'
# 3. cleanup!
# 4. commit
# 5. push
# 6. send pull request
# 7. do it again!

begin
  require 'yaml'
  require 'net/http'
  require 'net/https'
rescue
  puts $!
end

ROOT = File.expand_path(File.dirname(__FILE__) + '/../')

class Bot
  VERSION = '0.2'

  def initialize
    @config = YAML.load_file("#{ROOT}/config.yml")
    puts "Hi! This is Greedy Bot, I'm up and ready to eat your code today."
  end

  def run!
    repositories = @config['repositories']
    puts "#{repositories.count} repos found: #{repositories.map{|r| r['name']}.join ', '}"

    repositories.each do |r|
      repo = repository(
        :name => r['name'],
        :branch => r['branch']
      )
      puts "Processing repo #{repo}..."

      puts "Syncing..."
      update_repo repo
      puts "Cleaning up..."
      clean_repo repo

      if @config['upload']
        puts "Uploading..."
        push_cleanup_branch repo
        send_pull_request repo
      else
        puts "Don't upload as requested, you may want to check out in #{repo.path} now."
      end

      puts "#{repo} done."
    end
  end


  private

  def update_repo repo
    Dir.chdir ROOT
    Dir.mkdir @config['cache_dir'] unless File.directory? @config['cache_dir']
    Dir.chdir @config['cache_dir']
    if File.directory? repo.path
       Dir.chdir repo.path
       `git reset --hard -q`
       `git clean -df`
       `git checkout -q #{repo.branch}`
       `git branch -D #{@config['clean_branch']}`
       `git pull -qu origin #{repo.branch}`
    else
       `git clone -b #{repo.branch} #{repo.location}`
       Dir.chdir repo.path
    end
    raise 'Really?!' if `git branch #{@config['clean_branch']}` =~ /^fatal/
  end

  def clean_repo repo
    Dir.chdir repo.path
    `git checkout -q #{@config['clean_branch']}`

    find = <<-CMD.split("\n").map(&:strip).join(' ')
      find . -type f -not -wholename './.git*'
      #{@config['exclude_paths'].map{|path| "-not -wholename '#{path}' "}}
      -print0 | xargs -0 file -I | grep -v 'charset=binary' | cut -d: -f1
    CMD
    `#{find}`.each do |file|
      `sed -i '' -e 's/[ \t]*$//' #{file}`
    end

    `git commit -am 'Cleanup trailing whitespaces'`
  end

  def push_cleanup_branch repo
    Dir.chdir repo.path
    `git push origin #{@config['clean_branch']}`
  end

  def send_pull_request repo
    title = "Cleanup trailing whitespaces"
    body = <<-BLAH.split("\n").map(&:strip).join(' \\n')
      Hi! I'm the Greedy Bot and I'm starving!
      I ate all trailing whitespaces in your repo and offer you a clean code.
      I also added a newline at the end of files that didn't have one yet.
      Please double check I didn't eat useful stuff and merge this pull request if you fancy it.
      In the unlikely case I'd have done something nasty, please send me a pull request to fix me ;).

      Cheers, the Greedy Bot v#{VERSION}.
    BLAH

    path = "/repos/#{github_user_from_url @config['base_url']}/#{repo.name}/pulls"
    payload = <<-JSON.strip
      {
        "title": "#{title}",
        "body": "#{body}",
        "head": "#{@config['clean_branch']}",
        "base": "#{repo.branch}"
      }
    JSON

    post = Net::HTTP::Post.new(path, initheader = {'Content-Type' =>'application/json'})
    post.basic_auth @config['username'], @config['password']
    post.body = payload

    req = Net::HTTP.new('api.github.com', 443)
    req.use_ssl = true
    response = req.request(post)

    unless response.code == 201
      raise "Oops #{response.code} - #{response.message}: #{response.body}"
    end
  end

  def repository params
    Repository.new params.merge(:config => @config)
  end

  def github_user_from_url url
    url.split(':').last
  end

end

class Repository

  attr_accessor :name, :branch, :location, :path

  def initialize params
    @name = params[:name]
    @branch = params[:branch]
    @location = "#{params[:config]['base_url']}/#{params[:name]}"
    @path = "#{ROOT}/#{params[:config]['cache_dir']}/#{params[:name]}"
  end

  def to_s
    @name
  end

end

