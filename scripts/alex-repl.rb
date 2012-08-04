# Alex REPL for VX ACE
# Author: Kal
# Version: 1.0
#
# --- Usage ---
#
# First you should know what a binding in Ruby is. A binding is a context
# that you can get from some point in your program and it encapsulates the
# value of self, all instance varaibles and methods at that point.
# These can later be accessed via the binding object.
#
# To start an Alex session call the alex method on a binidng. You can get
# the current Binding instance by calling Kernel#binding.
# Example: binding.alex
# This will get the current binding and start an alex session.
#
# You can put that line anywhere in the editor or in an event script call.
# It will start an Alex session at the point in the program where the line
# is executed and you will be able to access everything you normally would
# be able to access at that point in the Alex session.
#
# When you start a session the game will pause (don't worry if it becomes
# unresponsive, this is normal) and you can type in code in the Console that 
# is then evaluated, and the return value is printed.
#
# To stop an Alex session and return to the game, type in exit.
#
# To clear the Console screen type in cls.
#
# When you are in an Alex session it is useful to be able to call instance_eval
# on object (instance_eval allows you to execute code from outside an object
# as if you were inside the object). Therefore Alex provides a shortcut to
# instance eval called 'ie'. Example: 1.ie("self") => 1
#
# Another thing you can do in Alex is define common methods for things you
# want to use frequently in Alex session so you don't have to type them
# in every time. You can put those method in the Common module. Have a look
# there to see some examples.
#
# You can also start an Alex session anywhere when playing the game
# by pressing a predefined key. This will start a session with the 
# current binding as the context. The default key is D but this can be
# customized in the CONFIG module.
#

module Kal
  module Alex
    
    module CONFIG
      # The key that when pressed will start Alex with the current binding.
      # For a list of keys, start a game, press F1 => Keyboard.
      # Z => D key.
      START_KEY = Input::Z
      # The string that prompts the user for input in an Alex session.
      INPUT_PROMPT = "alex: "
    end
    
    #
    # Here you can define method for common REPL strings that you type
    # in a lot. These methods are available to use in any Alex session.
    # They are called dynamically and will not polute the global namespace.
    # Note: if there is another method in the context that Alex is run in
    # with the same name as one of these methods, that method will always
    # be called, and the method defined here ignored.
    #
    module Common
      class << self
      
        #
        # Gets the nth Game_Actor instance.
        #
        def actor(n)
          $game_actors[n]
        end
        
        #
        # Gets the nth Game_Enemy instance.
        #
        def enemy(n)
          $game_troop.members[n - 1]
        end
        
      end
    end
    
    #
    # << END CONFIGURATION >>
    #
    
    #
    # A singleton class that implements the an IRB-like REPL.
    # Supports indentation.
    #
    class REPL
      attr_accessor :running    # If an Alex session is running or not.
      
      TEMP_PATH = "#{ENV["TEMP"]}\\temp-alex"   # File to surpress STDOUT.
      INDENT_SPACES = 2                         # Number of spaces per indent.
      
      # Keywords that will trigger an indent:
      INDENT_FIRST = %w[def class module while until begin if unless]
      INDENT_LAST = %w[do]
      
      def initialize
        @running = false
        @temp_file = File.new(TEMP_PATH, "w")
      end
      
      #
      # Starts an Alex session. Gets input until is is syntax valid and
      # then evals it. Loop until input is "exit".
      # Context is the Binding instance where the input will be evaluated in.
      #
      def start(context)
        @running = true
        loop do
          print Kal::Alex::CONFIG::INPUT_PROMPT
          input = get_input_until_valid
          
          if input == "exit"
            @running = false
            break
          end
          
          begin
            return_value = context.eval(input)
          rescue Exception => e
            puts "Error: #{e.message}"
          end
        
          puts "=> #{return_value.inspect}"
        end
      end
      
      #
      # Gets lines of input and add them together until they form a valid
      # Ruby string. Then return the string.
      #
      def get_input_until_valid
        buffer = ""                 # Buffer for input lines.
        indent = ""                 # The indent level.
        loop do
          line = gets
          buffer << line
          break if is_valid_syntax?(buffer)
 
          print Kal::Alex::CONFIG::INPUT_PROMPT
          if increases_indent_level?(line)
            indent.concat(" " * INDENT_SPACES)
            print indent
          elsif decreases_indent_level?(line)
            indent[-INDENT_SPACES..-1] = ""
            print indent
          else
            print indent
          end
        end
        buffer.chomp
      end
      
      #
      # Returns true if and only if a string does not throw a SyntaxError
      # when evaluated. Supresses standard output to prevent unwanted 
      # prints.
      #
      def is_valid_syntax?(string)
        begin
          begin
            surpress_stdout { eval(string) }
          rescue SyntaxError
            return false
          end
        rescue Exception
          # do nothing
        end
        true
      end
      
      #
      # Changes $stdout (which is the console) to the temp file.
      # Next executes the block.
      #
      def surpress_stdout
        stdout_orig = $stdout
        $stdout = @temp_file
        begin
          yield
        ensure
          $stdout = stdout_orig
        end
      end
      
      #
      # Checks to see if an input line should increase the indent level.
      # Compare the first and last token with the list of tokens that
      # increases indent level.
      #
      def increases_indent_level?(input)
        first_token = input[/\A([\w\d]+?)\s/, 1]
        last_token = input.chomp[/[\w\d]+\z/]
        result_first = first_token && INDENT_FIRST.include?(first_token)
        result_last = last_token && INDENT_LAST.include?(last_token)
        
        result_first || result_last
      end
      
      #
      # Indent is only decreased if the last token is 'end'. Does not
      # handle '}' to make it simpler.
      #
      def decreases_indent_level?(input)
        last_token = input.chomp[/[\w\d]+\z/]
        last_token == "end"
      end
      
      # Singleton implementation:
      
      @@instance = REPL.new      # The singleton instance.
      
      def self.instance          # Use this to get to the instance.
        @@instance
      end
                                  
      private_class_method :new  # Now we're really a singleton!
    end
    
  end
end

class Object
  
  #
  # Aliases the method_missing method that gets called whenever a method
  # is called that could not be found. If Alex is running and Alex::Common
  # responds to the method that was not found then delegate it to Alex::Common.
  #
  alias_method :method_missing_orig_alex, :method_missing
  def method_missing(method, *args, &block)
    if Kal::Alex::REPL.instance.running && Kal::Alex::Common.respond_to?(method)
      Kal::Alex::Common.send(method, *args, &block)
    else
      method_missing_orig_alex(method, *args, &block)
    end
  end
end


#
# You can get a binding object for the current binding by calling the
# Kernel#binding method and then start an Alex session by calling alex
# on that binding.
#
class Binding
  def alex
    Kal::Alex::REPL.instance.start(self)
  end
end


#
# Adds a check to the update method in scene base to see if the user
# pressed the Alex start key and if so start an Alex session.
#
class Scene_Base
  alias_method :update_alex_kal, :update
  def update
    update_alex_kal
    update_alex_start_key_kal
  end
  
  def update_alex_start_key_kal
    if Input.trigger?(Kal::Alex::CONFIG::START_KEY)
      Kal::Alex::REPL.instance.start(binding)
    end
  end
end
  
module Kernel
  def cls
    system("cls") # Clears the console.
  end
end

class BasicObject
  alias_method :ie, :instance_eval  # For quicker access.
end
