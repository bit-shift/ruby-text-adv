class String
  def title_case
    common_nouns = %w{of the a an}
    downcase.split(" ").each_with_index
            .map { |w, i| (i != 0 and common_nouns.include? w) ? w : w.capitalize }.join " "
  end
end

module Directions
  North = :north
  East  = :east
  South = :south
  West  = :west
  Up    = :up
  Down  = :down

  Vertical  = [:up, :down]

  Cardinal = [:north, :east, :south, :west]

  SemiCardinal = [[:north, :east], [:north, :west],
                  [:south, :west], [:south, :east]]

  All = Cardinal + SemiCardinal + Vertical

  def self.opposite(d)
    if d.respond_to? :map
      d.map { |d| Directions.opposite d }
    else
      case d
      when :north; :south
      when :east;  :west
      when :south; :north
      when :west;  :east
      when :up;    :down
      when :down;  :up
      end
    end
  end

  def self.parse(input)
    All.each do |d|
      names = []
      if d.respond_to? :join
        d_strs = d.map{ |subd| subd.to_s.downcase }
        names << d_strs.join
        names << d_strs.join(" ")
        names << d_strs.join("-")
        names << d_strs.map{ |subd| subd[0] }.join
      else
        d_str = d.to_s.downcase
        names << d_str
        names << d_str[0]
      end

      if names.include? input.downcase
        return d
      end
    end

    nil
  end

  def self.describe(d, omit_prefix=false)
    if d.respond_to? :map
      desc = d.map{ |d| Directions.describe d, true }.join "-"
    else
      desc = case d
      when :up
        "above"
      when :down
        "below"
      else
        d.to_s
      end
    end

    unless (Vertical.member? d) or omit_prefix
      desc = "to the " + desc
    end

    desc
  end
end

class Item
  attr_reader :name
  attr_reader :synonyms
  attr_reader :description
  attr_reader :use_action
  attr_accessor :location
  attr_reader :flags

  def initialize(world, location=nil, &block)
    @world = world
    @location = location
    @flags = []
    instance_eval &block
  end

private
    def named(name, *synonyms)
      @name = name
      @synonyms = synonyms
    end

    def desc(description)
      @description = description
    end

    def mark_as(*flags)
      flags.each { |f| @flags.push f }
    end

    def on_use(&block)
      @use_action = block
    end
end

class Room
  attr_reader :name
  attr_reader :title
  attr_reader :description
  attr_accessor :contents
  attr_accessor :exits

  def initialize(world, &block)
    @world = world
    @contents = []
    @exits = Hash.new
    instance_eval &block
  end

  def connect_to(direction, target_room, mutual=true)
    @exits[direction] = target_room
    if mutual
      target_room.exits[Directions.opposite direction] = self
    end
  end

private

    def add_item(&block)
      item = Item.new @world, self, &block
      @contents.push item
      item
    end

    def named(name)
      @name = name
      @title = name.title_case
    end

    def desc(description)
      @description = description
    end
end

class World
  attr_reader :starting_room

  def initialize(&block)
    @rooms = []
    instance_eval &block
  end

  def run
    @current_room = @starting_room
    @previous_room = nil
    @seen_rooms = []
    @inventory = @starting_inventory || []
    @running = true
    @quit_type = :soft_quit

    if @preamble
      puts @preamble
      puts "\n---\n\n"
    end

    while @running
      if @previous_room != @current_room
        @previous_room = @current_room
        describe_room
      end

      result = parse_command (ask "What now?")
      puts

      if result.is_a? Array
        run_command result
      elsif result.nil?
        puts "I didn't quite understand that."
      else  # error message
        puts result
      end
    end

    @quit_type
  end

  def game_over
    puts "\n==== Oh no! Game over, you lost. ===="
    @running = false
  end

  def win
    puts "\n==== Hooray! You won! ===="
    @running = false
  end

private
  
    def ask(question, prompt="> ")
      print ("\n" << question << "\n" << prompt)
      ($stdin.gets || "bye").chomp
    end

    def describe_room(force_full_desc=false)
      puts "<< #{@current_room.title} >>"
      
      unless force_full_desc or !(@seen_rooms.include? @current_room)
        return
      end

      puts @current_room.description

      unless @current_room.exits.empty?
        puts
        @current_room.exits.each do |direction, room|
          puts "#{Directions.describe(direction).capitalize} is #{room.name}."
        end
      end

      unless @current_room.contents.empty?
        puts
        puts "Glancing around, you can see:"
        @current_room.contents.each do |item|
          puts "\t#{item.name}"
        end
      end
      
      unless @seen_rooms.include? @current_room
        @seen_rooms.push @current_room
      end
    end

    def show_inventory
      if @inventory.empty?
        puts "You don't have anything on you right now."
      else
        puts "You have:"
        @inventory.each do |item|
          puts "\t#{item.name}"
        end
      end
    end

    def move_to(direction)
      if @current_room.exits[direction]
        @current_room = @current_room.exits[direction]
      else
        puts "You can't go that way."
      end
    end

    def match_items(item_string, *item_sources)
      item_list = []

      if item_sources.empty?
        item_sources = [@inventory]
      end

      item_sources.each do |item_source|
        if item_source.is_a? Room
          item_list += item_source.contents
        else
          item_list += item_source
        end
      end

      item_string.downcase!

      exact_matches = []
      word_matches = []
      prefix_matches = []
      initial_matches = []

      item_list.each do |item|
        item_names = ([item.name] + item.synonyms).map{ |n| n.downcase }

        if item_names.include? item_string
          exact_matches << item
        end

        unless item_names.select{ |n| n.split.include? item_string }.empty?
          word_matches << item
        end

        unless item_names.select{ |n| n.start_with? item_string }.empty?
          prefix_matches << item
        end

        unless item_names.select{ |n| n.split.map{ |w| w[0] } == item_string.each_char.to_a }.empty?
          initial_matches << item
        end
      end

      [exact_matches, word_matches, prefix_matches, initial_matches].reject{ |a| a.empty? }.first
    end

    def lookup_item(item_string, *item_sources)
      matches = match_items(item_string, *item_sources)

      if matches
        if matches.size == 1
          matches.first
        else
          puts "\n'#{item_string}' could mean multiple things:"
          matches.each_with_index { |item, n|
            maybe_in_inv = ", in inventory" unless item.location
            puts "\t#{item.name} (##{n + 1}#{maybe_in_inv})"
          }
          n = ask "Which did you mean?", "#"
          until n.empty? do
            begin
              return matches[Integer(n) - 1]
            rescue
              n = ask "I didn't understand that. Which did you mean again?", "#"
            end
          end
        end
      end
    end

    def describe_item(item)
      puts (item.description || "There's nothing particularly remarkable about it.")
    end

    def use_item(use_type, item)
      if (item.flags.include? :usable) and item.use_action
        if use_type != "use"
          needed_flag = case use_type
          when "drink", "quaff"
            :drinkable
          when "eat"
            :edible
          when "touch", "press", "push"
            :pressable
          end

          unless item.flags.include? needed_flag
            puts "You can't #{use_type} that!"
            return
          end
        end

        if (item.instance_eval &item.use_action) == :destroy
          if item.location
            item.location.contents.reject! { |i| i == item }
          else
            @inventory.reject! { |i| i == item }
          end
        end
      else
        puts "You can't #{use_type} that right now."
      end
    end

    def get_item(item)
      if item.flags.include? :fixed
        puts "You can't seem to move that. You leave it where it is."
      else
        item.location = nil
        @inventory.push item
        @current_room.contents.reject! { |i| i == item }
        puts "You put it in your inventory."
      end
    end

    def put_item(item)
      item.location = @current_room
      @current_room.contents.push item
      @inventory.reject! { |i| i == item }
      puts "You find somewhere suitable, and put it down."
    end

    def parse_command(input)
      command = input.downcase.split(" ")
      case command.first
      when "bye"
        [:quit]
      when "restart"
        [:restart]
      when "again", "."
        [:repeat]
      when "wait", "z"
        [:wait]
      when "inventory", "inv", "i"
        [:inventory]
      when "look", "l"
        [:look]
      when "examine", "x"
        unless command.size == 1
          item = lookup_item command[1..-1].join(" "), @inventory, @current_room
          if item
            [:examine, item]
          else
            "That doesn't seem to be something you can see."
          end
        end
      when "use", "drink", "quaff", "eat", "touch", "press", "push"
        unless command.size == 1
          item = lookup_item command[1..-1].join(" "), @inventory, @current_room
          if item
            [:use, command.first, item]
          else
            "That doesn't seem to be something you can get at."
          end
        end
      when "get", "take"
        unless command.size == 1
          item = lookup_item command[1..-1].join(" "), @current_room
          if item
            [:get, item]
          else
            "That doesn't seem to be here."
          end
        end
      when "drop"
        unless command.size == 1
          item = lookup_item command[1..-1].join(" ")
          if item
            [:put, item]
          else
            "You don't seem to have that."
          end
        end
      when "go"
        direction = Directions::parse command[1..-1].join(" ")
        if direction
          [:move, direction]
        end
      else  # try a direction, since those should be available bare
        direction = Directions::parse input
        if direction
          [:move, direction]
        end
      end
    end

    def run_command(command)
      if command == [:repeat]
        if @previous_command
          command = @previous_command
        else
          puts "No previous command to repeat."
          return
        end
      end

      case command.first
      when :wait
        puts "You wait around. Ho-hum."
      when :look
        describe_room true
      when :inventory
        show_inventory
      when :examine
        describe_item command.last
      when :use
        use_item command[1], command.last
      when :get
        get_item command.last
      when :put
        put_item command.last
      when :move
        move_to command.last
      when :restart
        @running = false
        @quit_type = :restart
      when :quit
        puts "Goodbye!"
        @running = false
        @quit_type = :hard_quit  # don't ask to play again
      end
      @previous_command = command
    end

    def add_room(&block)
      room = Room.new self, &block
      @rooms.push room
      room
    end

    def intro(*lines)
      @preamble = lines.join "\n"
    end
end


$repeat = true
while $repeat do
  mini_world = World.new do
    intro "==== TINY HOUSE ADVENTURE ====",
          "",
          "It's no Colossal Cave Adventure, that's for sure."

    living_room = add_room{
      named "a living room"
      desc "This is a room for living in. It looks rather un-lived-in. How ironic."
      add_item{
        named "blue potion", "potion"
        desc "A bubbly blue potion. It doesn't *seem* to be poisonous..."
        mark_as :usable, :drinkable
        on_use{
          puts "You fool! It was poison!"
          @world.game_over
          :destroy
        }
      }
    }

    secret_cave = add_room {
      named "a mysterious cave"
      desc "You never realized there was a cave under your yard, but well, here it is."
      add_item{
        named "yellow button", "button"
        desc "It's not as big as the red button, but it's happy with its size."
        mark_as :usable, :fixed, :pressable
        on_use{
          puts "Your vision blanks out, and when you come to, you're surrounded by"
          puts "cute little foxes. You're not sure how they got here, but frankly"
          puts "you don't care either."
          @world.win
        }
      }
    }

    outside = add_room{
      named "your yard"
      desc "It's a yard. What more can I say?"
      add_item{
        named "big red button", "big button", "red button", "button"
        desc "It's big. And red."
        mark_as :usable, :fixed, :pressable
        on_use{
          if @activated
            puts "You press the button again, but nothing else happens."
          else
            @activated = true
            puts "As you press the button, you hear a faint rumbling sound."
            puts
            puts "Suddenly, the ground opens up a little to your left, leaving"
            puts "an astonishingly neat hole down into the ground. Huh."
            @location.exits[Directions::Down] = secret_cave
          end
        }
      }
    }

    atrium = add_room{
      named "the atrium"
      desc "This looks like an unusually wide entry area compared to the room it adjoins."
    }

    living_room.connect_to Directions::South, atrium
    atrium.connect_to Directions::South, outside

    @starting_room = living_room
  end

  case mini_world.run
  when :hard_quit
    $repeat = false
  when :soft_quit
    print "\nPlay again? [y/N]  "
    unless ($stdin.gets || "no").chomp[0] == "y"
      $repeat = false
    end
  end

  if $repeat
    5.times { print "\n" }
  end
end