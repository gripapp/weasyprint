require 'spec_helper'

def app; Rack::Lint.new(@app); end

def mock_app(options = {}, conditions = {}, custom_headers = {}, body = nil)
  main_app = lambda { |env|
    @env = env
    full_headers = headers.merge custom_headers
    [200, full_headers, body || @body || ['Hello world!']]
  }

  builder = Rack::Builder.new
  builder.use WeasyPrint::Middleware, options, conditions
  builder.run main_app
  @app = builder.to_app
end

# A Rack body that is enumerable but not an Array, so it exercises the #each path rather than the
# #to_ary fast path, and records whether Rack's required #close was called.
class EnumerableBody
  attr_reader :closed

  def initialize(parts)
    @parts = parts
    @closed = false
  end

  def each(&block)
    @parts.each(&block)
  end

  def close
    @closed = true
  end
end

# A Rack 3 streaming body: responds only to #call, and so cannot be buffered.
class StreamingBody
  def call(stream)
    stream.write('Hello world!')
  ensure
    stream.close
  end
end

describe WeasyPrint::Middleware do
  let(:headers) { {header_name('Content-Type') => "text/html"} }

  describe "#call" do
    describe "caching" do
      let(:headers) do
        {
          header_name('Content-Type') => "text/html",
          header_name('ETag') => 'foo',
          header_name('Cache-Control') => 'max-age=2592000, public'
        }
      end

      context "by default" do
        before { mock_app }

        it "deletes ETag" do
          get 'http://www.example.org/public/test.pdf'
          expect(last_response.headers["ETag"]).to be_nil
        end
        it "deletes Cache-Control" do
          get 'http://www.example.org/public/test.pdf'
          expect(last_response.headers["Cache-Control"]).to be_nil
        end
      end

      context "when on" do
        before { mock_app({}, :caching => true) }

        it "preserves ETag" do
          get 'http://www.example.org/public/test.pdf'
          expect(last_response.headers["ETag"]).not_to be_nil
        end
        it "preserves Cache-Control" do
          get 'http://www.example.org/public/test.pdf'
          expect(last_response.headers["Cache-Control"]).not_to be_nil
        end
      end
    end

    describe "conditions" do
      describe ":only" do

        describe "regex" do
          describe "one" do
            before { mock_app({}, :only => %r[^/public]) }

            context "matching" do
              specify do
                get 'http://www.example.org/public/test.pdf'
                expect(last_response.headers["Content-Type"]).to eq("application/pdf")
                expect(last_response.body).to start_with("%PDF")
              end
            end

            context "not matching" do
              specify do
                get 'http://www.example.org/secret/test.pdf'
                expect(last_response.headers["Content-Type"]).to eq("text/html")
                expect(last_response.body).to eq("Hello world!")
              end
            end
          end # one regex

          describe "multiple" do
            before { mock_app({}, :only => [%r[^/invoice], %r[^/public]]) }

            context "matching" do
              specify do
                get 'http://www.example.org/public/test.pdf'
                expect(last_response.headers["Content-Type"]).to eq("application/pdf")
                expect(last_response.body).to start_with("%PDF")
              end
            end

            context "not matching" do
              specify do
                get 'http://www.example.org/secret/test.pdf'
                expect(last_response.headers["Content-Type"]).to eq("text/html")
                expect(last_response.body).to eq("Hello world!")
              end
            end
          end # multiple regex
        end # regex

        describe "string" do
          describe "one" do
            before { mock_app({}, :only => '/public') }

            context "matching" do
              specify do
                get 'http://www.example.org/public/test.pdf'
                expect(last_response.headers["Content-Type"]).to eq("application/pdf")
                expect(last_response.body).to start_with("%PDF")
              end
            end

            context "not matching" do
              specify do
                get 'http://www.example.org/secret/test.pdf'
                expect(last_response.headers["Content-Type"]).to eq("text/html")
                expect(last_response.body).to eq("Hello world!")
              end
            end
          end # one string

          describe "multiple" do
            before { mock_app({}, :only => ['/invoice', '/public']) }

            context "matching" do
              specify do
                get 'http://www.example.org/public/test.pdf'
                expect(last_response.headers["Content-Type"]).to eq("application/pdf")
                expect(last_response.body).to start_with("%PDF")
              end
            end

            context "not matching" do
              specify do
                get 'http://www.example.org/secret/test.pdf'
                expect(last_response.headers["Content-Type"]).to eq("text/html")
                expect(last_response.body).to eq("Hello world!")
              end
            end
          end # multiple string
        end # string

      end

      describe ":except" do

        describe "regex" do
          describe "one" do
            before { mock_app({}, :except => %r[^/secret]) }

            context "matching" do
              specify do
                get 'http://www.example.org/public/test.pdf'
                expect(last_response.headers["Content-Type"]).to eq("application/pdf")
                expect(last_response.body).to start_with("%PDF")
              end
            end

            context "not matching" do
              specify do
                get 'http://www.example.org/secret/test.pdf'
                expect(last_response.headers["Content-Type"]).to eq("text/html")
                expect(last_response.body).to eq("Hello world!")
              end
            end
          end # one regex

          describe "multiple" do
            before { mock_app({}, :except => [%r[^/prawn], %r[^/secret]]) }

            context "matching" do
              specify do
                get 'http://www.example.org/public/test.pdf'
                expect(last_response.headers["Content-Type"]).to eq("application/pdf")
                expect(last_response.body).to start_with("%PDF")
              end
            end

            context "not matching" do
              specify do
                get 'http://www.example.org/secret/test.pdf'
                expect(last_response.headers["Content-Type"]).to eq("text/html")
                expect(last_response.body).to eq("Hello world!")
              end
            end
          end # multiple regex
        end # regex

        describe "string" do
          describe "one" do
            before { mock_app({}, :except => '/secret') }

            context "matching" do
              specify do
                get 'http://www.example.org/public/test.pdf'
                expect(last_response.headers["Content-Type"]).to eq("application/pdf")
                expect(last_response.body).to start_with("%PDF")
              end
            end

            context "not matching" do
              specify do
                get 'http://www.example.org/secret/test.pdf'
                expect(last_response.headers["Content-Type"]).to eq("text/html")
                expect(last_response.body).to eq("Hello world!")
              end
            end
          end # one string

          describe "multiple" do
            before { mock_app({}, :except => ['/prawn', '/secret']) }

            context "matching" do
              specify do
                get 'http://www.example.org/public/test.pdf'
                expect(last_response.headers["Content-Type"]).to eq("application/pdf")
                expect(last_response.body).to start_with("%PDF")
              end
            end

            context "not matching" do
              specify do
                get 'http://www.example.org/secret/test.pdf'
                expect(last_response.headers["Content-Type"]).to eq("text/html")
                expect(last_response.body).to eq("Hello world!")
              end
            end
          end # multiple string
        end # string

      end

      describe "saving generated pdf to disk" do
	before do
          #make sure tests don't find an old test_save.pdf
          File.delete('spec/test_save.pdf') if File.exist?('spec/test_save.pdf')
          expect(File.exist?('spec/test_save.pdf')).to be(false)
	end

        context "when header WeasyPrint-save-pdf is present" do
          it "should saved the .pdf to disk" do
	    headers = { header_name('WeasyPrint-save-pdf') => 'spec/test_save.pdf' }
            mock_app({}, {only: '/public'}, headers)
	    get 'http://www.example.org/public/test_save.pdf'
            expect(File.exist?('spec/test_save.pdf')).to be(true)
	  end

          it "should not raise when target directory does not exist" do
	    headers = { header_name('WeasyPrint-save-pdf') => '/this/dir/does/not/exist/spec/test_save.pdf' }
            mock_app({}, {only: '/public'}, headers)
            expect {
              get 'http://www.example.com/public/test_save.pdf'
            }.not_to raise_error
          end
        end

        context "when header WeasyPrint-save-pdf is not present" do
          it "should not saved the .pdf to disk" do
            mock_app({}, {only: '/public'}, {} )
	    get 'http://www.example.org/public/test_save.pdf'
            expect(File.exist?('spec/test_save.pdf')).to be(false)
          end
        end
      end
    end

  describe "remove .pdf from PATH_INFO and REQUEST_URI" do
    before { mock_app }

      context "matching" do

        specify do
          get 'http://www.example.org/public/file.pdf'
          expect(@env["PATH_INFO"]).to eq("/public/file")
          expect(@env["REQUEST_URI"]).to eq("/public/file")
          expect(@env["SCRIPT_NAME"]).to be_empty
        end
        specify do
          get 'http://www.example.org/public/file.txt'
          expect(@env["PATH_INFO"]).to eq("/public/file.txt")
          expect(@env["REQUEST_URI"]).to be_nil
          expect(@env["SCRIPT_NAME"]).to be_empty
        end
      end

      context "subdomain matching" do
        before do
          main_app = lambda { |env|
            @env = env
            @env['SCRIPT_NAME'] = '/example.org'
            headers = {header_name('Content-Type') => "text/html"}
            [200, headers, @body || ['Hello world!']]
          }

          builder = Rack::Builder.new
          builder.use WeasyPrint::Middleware
          builder.run main_app
          @app = builder.to_app
        end
        specify do
          get 'http://example.org/sub/public/file.pdf'
          expect(@env["PATH_INFO"]).to eq("/sub/public/file")
          expect(@env["REQUEST_URI"]).to eq("/sub/public/file")
          expect(@env["SCRIPT_NAME"]).to eq("/example.org")
        end
        specify do
          get 'http://example.org/sub/public/file.txt'
          expect(@env["PATH_INFO"]).to eq("/sub/public/file.txt")
          expect(@env["REQUEST_URI"]).to be_nil
          expect(@env["SCRIPT_NAME"]).to eq("/example.org")
        end
      end

    end
  end

  describe "#translate_paths" do
    before do
      @pdf = WeasyPrint::Middleware.new({})
      @env = { 'REQUEST_URI' => 'http://example.com/document.pdf', 'rack.url_scheme' => 'http', 'HTTP_HOST' => 'example.com' }
    end

    it "should correctly parse relative url with single quotes" do
      @body = %{<html><head><link href='/stylesheets/application.css' media='screen' rel='stylesheet' type='text/css' /></head><body><img alt='test' src="/test.png" /></body></html>}
      body = @pdf.send :translate_paths, @body, @env
      expect(body).to eq("<html><head><link href='http://example.com/stylesheets/application.css' media='screen' rel='stylesheet' type='text/css' /></head><body><img alt='test' src=\"http://example.com/test.png\" /></body></html>")
    end

    it "should correctly parse relative url with double quotes" do
      @body = %{<link href="/stylesheets/application.css" media="screen" rel="stylesheet" type="text/css" />}
      body = @pdf.send :translate_paths, @body, @env
      expect(body).to eq("<link href=\"http://example.com/stylesheets/application.css\" media=\"screen\" rel=\"stylesheet\" type=\"text/css\" />")
    end

    it "should correctly parse relative url with double quotes" do
      @body = %{<link href='//fonts.googleapis.com/css?family=Open+Sans:400,600' rel='stylesheet' type='text/css'>}
      body = @pdf.send :translate_paths, @body, @env
      expect(body).to eq("<link href='//fonts.googleapis.com/css?family=Open+Sans:400,600' rel='stylesheet' type='text/css'>")
    end

    it "should return the body even if there are no valid substitutions found" do
      @body = "NO MATCH"
      body = @pdf.send :translate_paths, @body, @env
      expect(body).to eq("NO MATCH")
    end
  end

  describe "#translate_paths with root_url configuration" do
    before do
      @pdf = WeasyPrint::Middleware.new({})
      @env = { 'REQUEST_URI' => 'http://example.com/document.pdf', 'rack.url_scheme' => 'http', 'HTTP_HOST' => 'example.com' }
      WeasyPrint.configure do |config|
        config.root_url = "http://example.net/"
      end
    end

    it "should add the root_url" do
      @body = %{<html><head><link href='/stylesheets/application.css' media='screen' rel='stylesheet' type='text/css' /></head><body><img alt='test' src="/test.png" /></body></html>}
      body = @pdf.send :translate_paths, @body, @env
      expect(body).to eq("<html><head><link href='http://example.net/stylesheets/application.css' media='screen' rel='stylesheet' type='text/css' /></head><body><img alt='test' src=\"http://example.net/test.png\" /></body></html>")
    end

    after do
      WeasyPrint.configure do |config|
        config.root_url = nil
      end
    end
  end

  it "should not get stuck rendering each request as pdf" do
    mock_app
    # false by default. No requests.
    expect(@app.send(:rendering_pdf?)).to be false

    # Remain false on a normal request
    get 'http://www.example.org/public/file'
    expect(@app.send(:rendering_pdf?)).to be false

    # Return true on a pdf request.
    get 'http://www.example.org/public/file.pdf'
    expect(@app.send(:rendering_pdf?)).to be true

    # Restore to false on any non-pdf request.
    get 'http://www.example.org/public/file'
    expect(@app.send(:rendering_pdf?)).to be false
  end

  describe "Rack version compatibility" do
    describe "response header casing" do
      # Rack 3 rejects uppercase header names; Rack 2 conventionally uses them. The middleware
      # has to read the upstream Content-Type and write its own headers correctly under both.

      it "converts when the upstream Content-Type uses the other casing" do
        # Deliberately the casing the *running* Rack version does not use, to prove the lookup is
        # genuinely case-insensitive rather than accidentally matching.
        other_casing = RACK3 ? 'Content-Type' : 'content-type'
        mock_app({}, {}, {}, ['Hello world!'])
        allow(self).to receive(:headers).and_return(other_casing => 'text/html')

        builder = Rack::Builder.new
        builder.use WeasyPrint::Middleware
        builder.run lambda { |env| [200, { other_casing => 'text/html' }, ['Hello world!']] }
        @app = builder.to_app

        # Bypass Rack::Lint here: on Rack 3 the deliberately-wrong casing is what we are testing
        # the middleware tolerates, and Lint would reject it before the middleware sees it.
        status, response_headers, body = @app.call(Rack::MockRequest.env_for('http://www.example.org/public/test.pdf'))

        expect(status).to eq(200)
        expect(body.join).to start_with("%PDF")
        content_type = response_headers['content-type'] || response_headers['Content-Type']
        expect(content_type).to eq('application/pdf')
      end

      it "writes header names the running Rack version accepts" do
        mock_app
        get 'http://www.example.org/public/test.pdf'

        expect(last_response.headers[header_name('Content-Type')]).to eq('application/pdf')
        expect(last_response.headers[header_name('Content-Length')]).to eq(last_response.body.bytesize.to_s)
      end
    end

    describe "response bodies" do
      it "converts an enumerable body that is not an Array" do
        body = EnumerableBody.new(['Hello ', 'world!'])
        mock_app({}, {}, {}, body)

        get 'http://www.example.org/public/test.pdf'

        expect(last_response.body).to start_with("%PDF")
      end

      it "closes the upstream body it consumed and replaced" do
        body = EnumerableBody.new(['Hello world!'])
        mock_app({}, {}, {}, body)

        get 'http://www.example.org/public/test.pdf'

        # Rack requires a body that is discarded be closed, or whatever it holds open leaks.
        expect(body.closed).to be(true)
      end

      it "passes a streaming body through without converting it" do
        skip "Rack 3 only" unless RACK3

        body = StreamingBody.new
        mock_app({}, {}, {}, body)

        # A streaming body cannot be buffered, so there is nothing to hand to weasyprint; the
        # middleware must return it untouched rather than raising or emitting an empty PDF.
        status, _headers, returned = @app.call(Rack::MockRequest.env_for('http://www.example.org/public/test.pdf'))

        expect(status).to eq(200)
        expect(returned).to be(body)
      end
    end
  end

end
