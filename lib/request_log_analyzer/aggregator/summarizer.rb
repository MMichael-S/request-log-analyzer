module RequestLogAnalyzer::Aggregator
  class Summarizer < Base
    class Definer
      attr_reader :trackers

      # Initialize tracker array
      def initialize
        @trackers = []
      end

      # Initialize tracker summarizer by duping the trackers of another summarizer
      # <tt>other</tt> The other Summarizer
      def initialize_copy(other)
        @trackers = other.trackers.dup
      end

      # Drop all trackers
      def reset!
        @trackers = []
      end

      # Include missing trackers through method missing.
      def method_missing(tracker_method, *args)
        track(tracker_method, *args)
      end

      # Helper function to initialize a tracker and add it to the tracker array.
      # <tt>tracker_class</tt> The class to include
      # <tt>optiont</tt> The options to pass to the trackers.
      def track(tracker_klass, value_field = {}, other_options = {})
        options = value_field.is_a?(Symbol) ? other_options.merge(value: value_field) : value_field.merge(other_options)
        tracker_klass = RequestLogAnalyzer::Tracker.const_get(RequestLogAnalyzer.to_camelcase(tracker_klass)) if tracker_klass.is_a?(Symbol)
        @trackers << tracker_klass.new(options)
      end
    end

    attr_reader :trackers
    attr_reader :warnings_encountered

    # Initialize summarizer.
    # Generate trackers from speciefied source.file_format.report_trackers and set them up
    def initialize(source, options = {})
      super(source, options)
      @warnings_encountered = {}
      @trackers = source.file_format.report_trackers
      setup
    end

    def setup
    end

    # Call prepare on all trackers.
    def prepare
      fail 'No trackers set up in Summarizer!' if @trackers.nil? || @trackers.empty?
      @trackers.each { |tracker| tracker.prepare }
    end

    # Pass all requests to trackers and let them update if necessary.
    # <tt>request</tt> The request to pass.
    def aggregate(request)
      @trackers.each do |tracker|
        tracker.update(request) if tracker.should_update?(request)
      end
    end

    # Call finalize on all trackers. Saves a YAML dump if this is set in  the options.
    def finalize
      @trackers.each { |tracker| tracker.finalize }
      save_results_dump(options[:yaml]) if options[:yaml]
    end

    # Saves the results of all the trackers in YAML format to a file.
    # <tt>filename</tt> The file to store the YAML dump in.
    def save_results_dump(filename)
      File.open(filename, 'w') { |file| file.write(to_yaml) }
    end

    # Exports all the tracker results to YAML. It will call the to_yaml_object method
    # for every tracker and combines these into a single YAML export.
    def to_yaml
      require 'yaml'
      trackers_export = @trackers.reduce({}) do |export, tracker|
        export[tracker.title] = tracker.to_yaml_object; export
      end
      YAML.dump(trackers_export)
    end

    # Call report on all trackers.
    # <tt>output</tt> RequestLogAnalyzer::Output object to output to
    def report(output)
      report_header(output)
      if source.parsed_requests > 0
        @trackers.each { |tracker| output.report_tracker(tracker) }
      else
        output.puts
        output.puts('There were no requests analyzed.')
      end
      report_footer(output)
    end

    # Generate report header.
    # <tt>output</tt> RequestLogAnalyzer::Output object to output to
    def report_header(output)
      output.title('Request summary')

      output.with_style(cell_separator: false) do
        output.table({ width: 20 }, { font: :bold }) do |rows|
          source.processed_files.each do |f|
            rows << ['Processed File:', f]
          end
          rows << ['Parsed lines:',     source.parsed_lines]
          rows << ['Skipped lines:',    source.skipped_lines]
          rows << ['Parsed requests:',  source.parsed_requests]
          rows << ['Skipped requests:', source.skipped_requests]
          rows << ['Warnings:', @warnings_encountered.map { |(key, value)| "#{key}: #{value}" }.join(', ')] if has_warnings?
        end
      end
      output << "\n"
    end

    # Generate report footer.
    # <tt>output</tt> RequestLogAnalyzer::Output object to output to
    def report_footer(output)
      if has_log_ordering_warnings?
        output.title('Parse warnings')

        output.puts 'Parsable lines were encountered without a header line before it. It'
        output.puts 'could be that logging is not setup correctly for your application.'
        output.puts 'Visit this website for logging configuration tips:'
        output.puts output.link('http://github.com/wvanbergen/request-log-analyzer/wikis/configure-logging')
        output.puts
      end
    end

    # Returns true if there were any warnings generated by the trackers
    def has_warnings?
      @warnings_encountered.reduce(0) { |result, (_, value)| result += value } > 0
    end

    # Returns true if there were any log ordering warnings
    def has_log_ordering_warnings?
      @warnings_encountered[:no_current_request] && @warnings_encountered[:no_current_request] > 0
    end

    # Store an encountered warning
    # <tt>type</tt> Type of warning
    # <tt>message</tt> Warning message
    # <tt>lineno</tt> The line on which the error was encountered
    def warning(type, _message, _lineno)
      @warnings_encountered[type] ||= 0
      @warnings_encountered[type] += 1
    end
  end
end
