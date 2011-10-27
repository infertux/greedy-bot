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
rescue
  puts $!
end

ROOT = File.expand_path(File.dirname(__FILE__) + '/../')

class Bot

  def initialize
    @config = YAML.load_file("#{ROOT}/config.yml")
    puts "Hi! This is GreedyBot, I'm up and ready to eat your code today."
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

      update_repo repo
      clean_repo repo
    end
  end

  private

  def update_repo repo
    Dir.chdir ROOT
    Dir.mkdir @config['cache_dir'] unless File.directory? @config['cache_dir']
    Dir.chdir @config['cache_dir']
    if File.directory? repo.path
       Dir.chdir repo.path
       `git reset --hard`
       `git clean -df`
       `git checkout #{repo.branch}`
       `git branch -D #{@config['clean_branch']}`
       `git pull -u origin #{repo.branch}`
    else
       `git clone -b #{repo.branch} #{repo.location}`
       Dir.chdir repo.path
    end
    raise 'Really?!' if `git branch #{@config['clean_branch']}` =~ /^fatal/
  end

  def clean_repo repo
    Dir.chdir ROOT
    raise 'WTF?' unless File.directory? repo.path
    Dir.chdir repo.path
    `git checkout #{@config['clean_branch']}`
    `find . -type f -not -wholename './.git*' -print0 | xargs -0 file -I | grep -v 'charset=binary' | cut -d: -f1`.each do |file|
      `sed -i '' -e 's/[ \t]*$//' #{file}`
    end
    # puts `git diff`
  end

  def repository params
    Repository.new params.merge(:config => @config)
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

