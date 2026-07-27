# frozen_string_literal: true

require "etc"
require "set"
require "yaml"

module CleoQualityReview
  ##
  # Configuration for file include/exclude patterns and runtime defaults
  class Configuration
    DEFAULT_CONFIG_PATH = File.expand_path("../../config/default.yml", __dir__)
    LOCAL_CONFIG_PATH = ".cleo_quality_review.yaml"
    ALL_TOOLS = "AllTools"
    INCLUDE = "Include"
    EXCLUDE = "Exclude"
    INHERIT_FROM = "inherit_from"
    GEM_DEFAULT_ALIASES = ["default", "gem:default"].freeze
    MATCH_FLAGS = File::FNM_PATHNAME | File::FNM_EXTGLOB

    ##
    # Load configuration from default and local config files
    # @param [String] root root directory for local config lookup
    # @return [Configuration]
    def self.load(root: Dir.pwd)
      Loader.new(root: root).load
    end

    ##
    # Resolve the configured worker count for concurrent checks.
    # @return [Integer] resolved worker count (at least 1)
    def self.max_concurrency
      max_concurrency_limit(env_max_concurrency || default_max_concurrency)
    end

    ##
    # Clamp a worker count to a usable lower bound.
    # @param [Integer] value worker count to clamp
    # @return [Integer] clamped worker count
    def self.max_concurrency_limit(value)
      [value.to_i, 1].max
    end

    ##
    # Read the max worker count from the environment, if configured.
    # @return [Integer, nil] the configured count, or nil when unset/blank
    # @raise [ArgumentError] if the environment value is not an integer
    def self.env_max_concurrency
      value = ENV["CLEO_QUALITY_REVIEW_MAX_CONCURRENCY"]
      value && !value.strip.empty? ? Integer(value) : nil
    end

    ##
    # @return [Integer] host processor count used as the default worker cap
    def self.default_max_concurrency
      Etc.nprocessors
    end

    ##
    # @param [Hash] data parsed configuration data
    def initialize(data)
      @data = data
    end

    ##
    # @return [Array<String>] glob patterns for files to include
    def include_patterns
      patterns_for(INCLUDE)
    end

    ##
    # @return [Array<String>] glob patterns for files to exclude
    def exclude_patterns
      patterns_for(EXCLUDE)
    end

    ##
    # Check if a file should be included based on configuration patterns
    # @param [String] path file path to check
    # @return [Boolean]
    def target_file?(path)
      normalized_path = normalize_path(path)

      matches_any?(include_patterns, normalized_path) && !matches_any?(exclude_patterns, normalized_path)
    end

    private

    attr_reader :data

    def patterns_for(key)
      Array(data.fetch(ALL_TOOLS) { {} }.fetch(key) { [] }).map(&:to_s)
    end

    def matches_any?(patterns, path)
      patterns.any? { |pattern| matches?(pattern, path) }
    end

    def matches?(pattern, path)
      normalized_pattern = normalize_pattern(pattern)

      File.fnmatch?(normalized_pattern, path, MATCH_FLAGS)
    end

    def normalize_path(path)
      path.to_s.delete_prefix("./").tr(File::ALT_SEPARATOR || File::SEPARATOR, File::SEPARATOR).tr("\\", "/")
    end

    def normalize_pattern(pattern)
      pattern.to_s.delete_prefix("./").tr("\\", "/")
    end

    ##
    # Loads and merges configuration files with inheritance support
    class Loader
      ##
      # @param [String] root root directory for config file lookup
      def initialize(root:)
        @root = File.expand_path(root)
      end

      ##
      # Load merged configuration
      # @return [Configuration]
      def load
        data = load_file(DEFAULT_CONFIG_PATH)
        local_config_path = File.join(root, LOCAL_CONFIG_PATH)
        data = merge(data, load_file(local_config_path)) if File.file?(local_config_path)

        Configuration.new(data)
      end

      private

      attr_reader :root

      def load_file(path, seen: Set.new)
        expanded_path = expand_config_path(path, relative_to: root)
        return {} if skip_file?(expanded_path, seen)

        seen.add(expanded_path)
        load_with_inheritance(expanded_path, seen)
      end

      def skip_file?(expanded_path, seen)
        return true if seen.include?(expanded_path)

        raise ArgumentError, "Config file not found: #{expanded_path}" unless File.file?(expanded_path)

        false
      end

      def load_with_inheritance(expanded_path, seen)
        config = read_yaml(expanded_path)
        inherited_data = load_inherited(config, expanded_path, seen)
        merge(inherited_data, config.except(INHERIT_FROM))
      end

      def load_inherited(config, expanded_path, seen)
        inherit_from(config).reduce({}) do |merged, inherited_path|
          merge(merged, load_file(resolve_inherited_path(inherited_path, expanded_path), seen: seen))
        end
      end

      def read_yaml(path)
        parsed = YAML.safe_load(File.read(path), aliases: true)
        return {} if parsed.nil?
        raise ArgumentError, "Config file must contain a YAML mapping: #{path}" unless parsed.is_a?(Hash)

        stringify_keys(parsed)
      end

      def inherit_from(config)
        Array(config.fetch(INHERIT_FROM) { [] })
      end

      def resolve_inherited_path(path, parent_path)
        value = path.to_s
        return DEFAULT_CONFIG_PATH if GEM_DEFAULT_ALIASES.include?(value)

        expand_config_path(value, relative_to: File.dirname(parent_path))
      end

      def expand_config_path(path, relative_to:)
        path_string = path.to_s
        return File.expand_path(path_string) if path_string.start_with?("/", "~")

        File.expand_path(path_string, relative_to)
      end

      def merge(base, override)
        base.merge(override) do |_key, base_value, override_value|
          merge_values(base_value, override_value)
        end
      end

      def merge_values(base_value, override_value)
        return merge(base_value, override_value) if both_hashes?(base_value, override_value)
        return (base_value + override_value).uniq if both_arrays?(base_value, override_value)

        override_value
      end

      def both_hashes?(a, b) = a.is_a?(Hash) && b.is_a?(Hash)

      def both_arrays?(a, b) = a.is_a?(Array) && b.is_a?(Array)

      def stringify_keys(value)
        case value
        when Hash then stringify_hash_keys(value)
        when Array then stringify_array_values(value)
        else value
        end
      end

      def stringify_hash_keys(hash)
        hash.to_h { |key, v| [key.to_s, stringify_keys(v)] }
      end

      def stringify_array_values(array)
        array.map { |v| stringify_keys(v) }
      end
    end
  end
end
