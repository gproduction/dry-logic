# frozen_string_literal: true

module Dry
  module Logic
    class Serialization
      def initialize(*args,
            compiler: RuleCompiler.new(*args).method(:call),
            parser: JSON.method(:parse),
            generator: JSON.method(:fast_generate)
          )
        @compiler, @parser, @generator = compiler, parser, generator
        @deserializer = AST >> @compiler >> Unsplat
        @serializer = BuildHash
        @loader = @parser >> @deserializer
        @dumper = @serializer >> @generator
      end

      attr_reader :compiler, :parser, :generator, :deserializer, :serializer, :loader, :dumper

      def load(json)
        @loader[json]
      end

      def dump(hsh)
        @dumper[hsh]
      end

      def deserialize(*input)
        @deserializer[input]
      end

      def serialize(input)
        @serializer[input]
      end

      HashBuilder = ::Struct.new(:type, :keys) do
        def call(node)
          keys.each_with_index.with_object({ type: type }) do |(key, n), hsh|
            hsh[key] =
              case key
              when :rule; HashMapper[*node[n]]
              when :rules; node[n].map(&SplatHashMapper)
              else node[n]
              end
          end
        end

        def to_proc
          @fn ||= method(:call).to_proc
        end
      end

      AST = proc do |input|
        case input
        when Hash
          input.size == 0 ? Undefined : LoadHash[input]
        when Array
          input.map(&AST)
        when 'Undefined'
          Undefined
        else
          input
        end
      end

      fetch_and_call_from = -> (map, key, value) { map[key].call(value) }.curry

      HashMap = begin
        map = {
          and:         %i[left right],
          attr:        %i[path rule],
          check:       %i[keys rule],
          each:        %i[rule],
          implication: %i[left right],
          key:         %i[path rule],
          negation:    %i[rule],
          or:          %i[left right],
          set:         %i[rules],
          xor:         %i[rules],
          predicate:   %i[name args]
        }
        map.each { |k, v| map[k] = HashBuilder.new(k, v) }
        map.freeze
      end

      Unsplat = proc { |input| input.is_a?(Array) && input.size == 1 ? input[0] : input }

      SplatCall = -> (fn, input) { fn.call(*input) }.curry

      HashMapper = fetch_and_call_from[HashMap]

      SplatHashMapper = SplatCall[HashMapper]

      NodeMap = Hash.new(AST).merge!(
        args: -> ary { ary.map { |(key, val)| [key, AST[val]] } }
      ).freeze

      NodeMapper = fetch_and_call_from[NodeMap]

      HashToNode = -> (type:, **hsh) do
        type = type.to_sym
        keys = HashMap.fetch(type).keys
        assoc = keys.map { |k| NodeMapper.(k, hsh[k]) }
        assoc = assoc[0] if keys.size == 1
        [type, assoc]
      end

      LoadHash = proc(&:symbolize_keys) >> HashToNode

      BuildHash = proc(&:to_ast) >> SplatHashMapper

      PredicateArg = proc { |ary| ary[-1] } >> AST

      def self.default_instance
        @default_instance ||= new()
      end

      instance_methods(false).each do |name|
        define_singleton_method(name, &instance_method(name).bind(default_instance))
      end
    end
  end
end
