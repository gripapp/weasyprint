class WeasyPrint

  class Middleware

    def initialize(app, options = {}, conditions = {})
      @app        = app
      @options    = options
      @conditions = conditions
      @render_pdf = false
    end

    def call(env)
      @request    = Rack::Request.new(env)
      @render_pdf = false
      # fetch, not delete: @conditions is the same Hash for every request this (long-lived,
      # shared-across-threads) middleware instance handles. delete permanently removed :caching
      # after the first request ever served, so caching: true silently stopped working from the
      # second request onward.
      @caching    = @conditions.fetch(:caching, false)

      set_request_to_render_as_pdf(env) if render_as_pdf?
      status, headers, response = @app.call(env)

      content_type = header(headers, 'Content-Type')
      content_type = content_type.first if content_type.is_a?(Array)

      if rendering_pdf? && content_type.to_s =~ /text\/html|application\/xhtml\+xml/
        html = buffer_body(response)

        # Rack 3 streaming bodies (those responding to #call rather than #each) cannot be
        # buffered, so there is nothing to convert - pass them through untouched.
        return [status, headers, response] if html.nil?

        begin
          body = WeasyPrint.new(translate_paths(html, env), @options).to_pdf
        ensure
          # The upstream body has been consumed and is being discarded; Rack requires it be
          # closed so whatever it holds open (file handles, DB connections) is released. This
          # must run even if to_pdf raises, or the body leaks on every failed conversion.
          response.close if response.respond_to?(:close)
        end
        response = [body]

        if (save_path = header(headers, 'WeasyPrint-save-pdf'))
          File.open(save_path, 'wb') { |file| file.write(body) } rescue nil
          delete_header(headers, 'WeasyPrint-save-pdf')
        end

        unless @caching
          # Do not cache PDFs
          delete_header(headers, 'ETag')
          delete_header(headers, 'Cache-Control')
        end

        set_header(headers, 'Content-Length', body.bytesize.to_s)
        set_header(headers, 'Content-Type', 'application/pdf')
      end

      [status, headers, response]
    end

    private

    # Rack 3 forbids uppercase characters in response header names, while Rack 2 and earlier
    # conventionally capitalize them. Read and delete case-insensitively so this middleware works
    # under both, and write using whichever casing the response is already using.

    def header(headers, name)
      headers[name] || headers[name.downcase] || begin
        _, value = headers.find { |key, _| key.casecmp(name).zero? }
        value
      end
    end

    def delete_header(headers, name)
      headers.delete(name)
      headers.delete(name.downcase)
      matching = headers.keys.select { |key| key.casecmp(name).zero? }
      matching.each { |key| headers.delete(key) }
    end

    def set_header(headers, name, value)
      correct_name = rack3? ? name.downcase : name

      # An existing key found only by case-insensitive match may be cased wrong for the running
      # Rack version (e.g. an upstream that emits "Content-Type" while running on Rack 3, which
      # forbids uppercase header names). Reusing that casing would just perpetuate the violation,
      # so drop it and write the correct one instead.
      matching = headers.keys.select { |key| key.casecmp(name).zero? && key != correct_name }
      matching.each { |key| headers.delete(key) }

      headers[correct_name] = value
    end

    def rack3?
      @rack3 = Gem::Version.new(Rack.release.to_s) >= Gem::Version.new('3.0') unless defined?(@rack3)
      @rack3
    end

    # Collect the upstream response body into a String. Returns nil when the body cannot be
    # buffered, which under Rack 3 means a streaming body that only responds to #call.
    #
    # The Rack 3 SPEC says middleware "must not call each directly" on an Enumerable Body - it
    # should instead return a new body that consumes the original lazily during its own #each.
    # That isn't possible here: converting HTML to PDF fundamentally requires the complete
    # content before this method can return, to compute the PDF and its final Content-Length.
    # Eager buffering is the deliberate, unavoidable consequence of what this middleware does,
    # not an oversight.
    def buffer_body(response)
      if response.respond_to?(:to_ary)
        response.to_ary.join
      elsif response.respond_to?(:each)
        buffered = +''
        response.each { |part| buffered << part }
        buffered
      elsif response.respond_to?(:body)
        # Rails' ActionDispatch::Response::RackBody always exposes #body, even when the
        # underlying stream is call-only (e.g. ActionController::Live). In that case
        # Response#body falls back to returning the raw stream object itself, which is not
        # string-like - only use the result if it actually is, or a call-only body here would
        # silently render as a PDF of that object's #to_s.
        content = response.body
        content.to_str if content.respond_to?(:to_str)
      end
    end

    # Change relative paths to absolute
    def translate_paths(body, env)
      # Host with protocol
      root = WeasyPrint.configuration.root_url || "#{env['rack.url_scheme']}://#{env['HTTP_HOST']}/"

      body.gsub(/(href|src)=(['"])\/([^\/]([^\"']*|[^"']*))['"]/, '\1=\2' + root + '\3\2')
    end

    def rendering_pdf?
      @render_pdf
    end

    def render_as_pdf?
      request_path_is_pdf = @request.path.match(%r{\.pdf$})

      if request_path_is_pdf && @conditions[:only]
        rules = [@conditions[:only]].flatten
        rules.any? do |pattern|
          if pattern.is_a?(Regexp)
            @request.path =~ pattern
          else
            @request.path[0, pattern.length] == pattern
          end
        end
      elsif request_path_is_pdf && @conditions[:except]
        rules = [@conditions[:except]].flatten
        rules.map do |pattern|
          if pattern.is_a?(Regexp)
            return false if @request.path =~ pattern
          else
            return false if @request.path[0, pattern.length] == pattern
          end
        end

        return true
      else
        request_path_is_pdf
      end
    end

    def set_request_to_render_as_pdf(env)
      @render_pdf = true

      path = @request.path.sub(%r{\.pdf$}, '')
      path = path.sub(@request.script_name, '')

      %w[PATH_INFO REQUEST_URI].each { |e| env[e] = path }

      env['HTTP_ACCEPT'] = concat(env['HTTP_ACCEPT'], Rack::Mime.mime_type('.html'))
      env['Rack-Middleware-WeasyPrint'] = 'true'
    end

    def concat(accepts, type)
      (accepts || '').split(',').unshift(type).compact.join(',')
    end

  end
end
