namespace Docker {
	
    public errordomain RequestError {
        FATAL,
        NOT_FOUND
    }
	
    public interface RepositoryInterface : GLib.Object {
        public abstract Image[]? get_images() throws RequestError;
    }

    public class UnixSocketRepository : RepositoryInterface, GLib.Object {
		
        private string socket_path;
		private SocketClient client = new SocketClient();
		
        public UnixSocketRepository(string socket_path) {
            this.socket_path = socket_path;
        }
		
		/**
		 * Retrieve the list of all images
		 */
        public Image[]? get_images() throws RequestError {
		
            try {
				
                string message = "GET /images/json HTTP/1.1\r\nHost: localhost\r\n\r\n";	
			
                return parse_image_payload(this.send(message).payload);

            } catch (RequestError e) {
				var message_builder = new StringBuilder();
                message_builder.printf(
					"Error while fetching images list from docker daemon at %s (%s)",
					this.socket_path,
					e.message
				);
                throw new RequestError.FATAL(message_builder.str);
            }
        }

		/**
		 * Retrieve a list of containers
		 */
        public Container[]? get_containers() throws RequestError {
		
            try {
				
                string message = "GET /containers/json HTTP/1.1\r\nHost: localhost\r\n\r\n";	
			
                return parse_container_payload(this.send(message).payload);

            } catch (RequestError e) {
				var message_builder = new StringBuilder();
                message_builder.printf(
					"Error while fetching container list from docker daemon at %s (%s)",
					this.socket_path,
					e.message
				);
                throw new RequestError.FATAL(message_builder.str);
            }
        }

        public RepositoryResponse response { get; private set;}
		
		/**
		 * Create the connection to docker daemon
		 */	
		private SocketConnection? create_connection() throws RequestError {
			try {
				return this.client.connect(new UnixSocketAddress(this.socket_path));	
			} catch (GLib.Error e) {
				var message_builder = new StringBuilder();
                message_builder.printf(
					"Error while fetching images list from docker daemon at %s (%s)",
					this.socket_path,
					e.message
				);
                throw new RequestError.FATAL(message_builder.str);
			}
		}
	
		/**
		 * Send a message to docker daemon and return the response
		 */ 
		private RepositoryResponse send(string message) throws RequestError{
			    
			var conn = this.create_connection();
			   
			try {
				conn.output_stream.write(message.data);	
			} catch(GLib.IOError e) {
				var message_builder = new StringBuilder();
                message_builder.printf(
					"Error while sending images list request to docker daemon at %s (%s)",
					this.socket_path,
					e.message
				);
                throw new RequestError.FATAL(message_builder.str);
			}

            return new RepositoryResponse(new DataInputStream(conn.input_stream));
		}

		/**
		 * Parse images payload
		 */ 
        private Image[] parse_image_payload(string payload) {

            Image[] images = {};
            try {
                var parser = new Json.Parser();
                parser.load_from_data(payload);
				
                var nodes = parser.get_root().get_array().get_elements();
		
                foreach (unowned Json.Node node in nodes) {
                    string[0] repotag = node.get_object().get_array_member("RepoTags").get_string_element(0).split(":", 2);

                    images += Image() {
                        id 		   = node.get_object().get_string_member("Id"),
                        created_at = (int64) node.get_object().get_int_member("Created"),
                        repository = repotag[0],
                        tag        = repotag[1]
                    };
                }
            } catch (Error e) {

                return images;
            }

            return images;
        }
        
		/**
		 * Parse containers payload
		 */ 
        private Container[] parse_container_payload(string payload) {

            Container[] containers = {};
            try {
                var parser = new Json.Parser();
                parser.load_from_data(payload);
				
                var nodes = parser.get_root().get_array().get_elements();
		
                foreach (unowned Json.Node node in nodes) {
                    containers += Container() {
                        id 		   = node.get_object().get_string_member("Id"),
                        created_at = (int64) node.get_object().get_int_member("Created"),
                        image_id   = node.get_object().get_string_member("ImageID"),
						command    = node.get_object().get_string_member("Command")
                    };
                }
            } catch (Error e) {

                return containers;
            }

            return containers;
        }
    }
	
    public class RepositoryResponse : Object {
		
        private int status;
        private Gee.HashMap<string, string> headers;

        public RepositoryResponse(DataInputStream stream) {

        try {
                status  = extract_response_status_code(stream);
                headers = extract_response_headers(stream);

                if (headers.has("Transfer-Encoding", "chunked")) {
                    stream.read_line(null);
                }

                payload = stream.read_line(null).strip();
                
                stream.close();
			
            } catch (IOError e) {
                stdout.printf(e.message);
            }
        }

        public string? payload { get; set;}
		
        private int? extract_response_status_code(DataInputStream stream) {
            
            try {
                string header_line = stream.read_line(null);
				
                Regex regex = new Regex("HTTP/(\\d.\\d) (\\d{3}) [a-zAZ]*");
                MatchInfo info;
                if (regex.match(header_line, 0, out info)){
                    return (int) info.fetch(2);
                }
            } catch (RegexError e) {
                return null;
            } catch (IOError e) {
                return null;
            }
			
            return null;
        }
		
        private Gee.HashMap<string, string>? extract_response_headers(DataInputStream stream) {
			
            var headers = new Gee.HashMap<string, string>();
            string header_line;

            try {
                while ((header_line = stream.read_line(null)).strip() != "") {
                    string[] _header = header_line.split(":", 2);                        
                    headers.set(_header[0], _header[1].strip());
                }
                
                return headers;
                
            } catch (RegexError e) {
                return null;
            } catch (IOError e) {
                return null;
            }
        }
	}

    public struct Image {
        public string id;
        public int64 created_at;
        public string repository;
        public string tag;
    }
    
    public struct Container {
        public string id;
        public int64 created_at;
        public string image_id;
        public string command;
    }
}












