using global::Dockery.DockerSdk;

public class ClientMock : Client.RestClient {

    public Io.Response response { get; set;}
    public Io.FutureResponse future_response { get; set;}

    public ClientMock() {
        this.response = new Io.Response();
        this.future_response = new Io.FutureResponse();
    }

    public override bool supportUri() {
        return true;
    }

    public override Io.Response send(string method, string endpoint, string? body = null) {
        return this.response;
    }

    public override Io.FutureResponse future_send(string method, string endpoint, string? body = null) {
        return this.future_response;
    }
}