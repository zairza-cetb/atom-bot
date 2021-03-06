require 'eventmachine'
require 'uri'
require 'websocket'

module EventMachine
    class WebSocketClient < Connection
        include Deferrable

        attr_accessor :url
        attr_accessor :protocol_version
        attr_accessor :origin

        def self.connect(uri, opts={})
            p_uri = URI.parse(uri)
            conn = EM.connect(p_uri.host, p_uri.port || 80, self) do |c|
                c.url = uri
                c.protocol_version = opts[:version]
                c.origin = opts[:origin]
            end
        end

        def post_init
            @handshaked = false
            @frame  = ::WebSocket::Frame::Incoming::Client.new
        end

        def connection_completed
            @connect.yield if @connect
            @hs = ::WebSocket::Handshake::Client.new(:url => @url,
                                                    :origin => @origin,
                                                    :version => @protocol_version)
            send_data @hs.to_s
        end

        def stream &cb; @stream = cb; end
        def connected &cb; @connect = cb; end
        def disconnect &cb; @disconnect = cb; end

        def receive_data data
            if !@handshaked
                @hs << data
                if @hs.finished?
                    @handshaked = true
                    succeed
                end

                receive_data(@hs.leftovers) if @hs.leftovers
            else
                @frame << data
                while msg = @frame.next
                    @stream.call(msg) if @stream
                end
            end
        end

        def send_msg(s, args={})
            type = args[:type] || :text
            frame = ::WebSocket::Frame::Outgoing::Client.new(:data => s, :type => type, :version => @hs.version)
            send_data frame.to_s
        end

        def unbind
            super
            @disconnect.call if @disconnect
        end
    end
end
