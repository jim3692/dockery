/*
 * ApplicationController is listening to all signals emitted by the view layer
 */
public class ApplicationController : GLib.Object {

    protected Sdk.Docker.Repository repository;
    protected Gtk.Window window;
    protected MessageDispatcher message_dispatcher;
    protected View.MainApplicationView view;

    public ApplicationController(Gtk.Window window, View.MainApplicationView view, MessageDispatcher message_dispatcher) {
        this.message_dispatcher = message_dispatcher;
        this.view               = view;
        this.window             = window;
    }

    public void listen_container_view() {

        view.containers.container_status_change_request.connect((requested_status, container) => {

            try {
                string message = "";
                if (requested_status == Sdk.Docker.Model.ContainerStatus.PAUSED) {
                    repository.containers().pause(container);
                    message = "Container %s successfully unpaused".printf(container.id);
                } else if (requested_status == Sdk.Docker.Model.ContainerStatus.RUNNING) {
                    repository.containers().unpause(container);
                    message = "Container %s successfully paused".printf(container.id);
                }
                this.init_container_list();
                message_dispatcher.dispatch(Gtk.MessageType.INFO, message);

            } catch (Sdk.Docker.RequestError e) {
                message_dispatcher.dispatch(Gtk.MessageType.ERROR, (string) e.message);
            }
        });

        view.containers.container_remove_request.connect((container) => {

            Gtk.MessageDialog msg = new Gtk.MessageDialog(
                window, Gtk.DialogFlags.MODAL,
                Gtk.MessageType.WARNING,
                Gtk.ButtonsType.OK_CANCEL,
                "Really remove the container %s (%s)?".printf(container.name, container.id)
            );

            msg.response.connect((response_id) => {
                switch (response_id) {
                    case Gtk.ResponseType.OK:
                    
                        try {
                            repository.containers().remove(container);
                        } catch (Sdk.Docker.RequestError e) {
                            message_dispatcher.dispatch(Gtk.MessageType.ERROR, (string) e.message);
                        }

                        this.init_container_list();                        
                        
                        break;
                    case Gtk.ResponseType.CANCEL:
                        break;
                    case Gtk.ResponseType.DELETE_EVENT:
                        break;
                }

                msg.destroy();

            });

            msg.show();
        });

        view.images.image_remove_request.connect((image) => {

            var dialog = new View.Dialog.with_buttons(350, 100, "Remove Docker image", window);

            dialog.add_button("No !", Gtk.ResponseType.CLOSE);
            Gtk.Widget yes_button = dialog.add_button("Yes !", Gtk.ResponseType.APPLY);
            yes_button.get_style_context().add_class("destructive-action");
            
            var body = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 5);
            
            Gtk.Label label = new Gtk.Label("Really remove image %s ?".printf(image.id));
            
            body.pack_start(label, false, true, 0);
            
            dialog.add_body(body);
            
            dialog.response.connect((source, response_id) => {

                switch (response_id) {
                    case Gtk.ResponseType.APPLY:
                    
                        try {
                            this.repository.images().remove(image);
                        } catch (Sdk.Docker.RequestError e) {
                            message_dispatcher.dispatch(Gtk.MessageType.ERROR, (string) e.message);
                        }

                        this.init_image_list();
                        dialog.destroy();
                        
                        break;
                    case Gtk.ResponseType.CANCEL:
                        break;
                    case Gtk.ResponseType.DELETE_EVENT:
                        break;
                    case Gtk.ResponseType.CLOSE:
                        break;                        
                }
                
                dialog.destroy();


            });

            dialog.show_all();
        });

        view.containers.container_start_request.connect((container) => {

            try {
                repository.containers().start(container);
                string message = "Container %s successfully started".printf(container.id);
                this.init_container_list();
                message_dispatcher.dispatch(Gtk.MessageType.INFO, message);

            } catch (Sdk.Docker.RequestError e) {
                message_dispatcher.dispatch(Gtk.MessageType.ERROR, (string) e.message);
                this.init_container_list();
            }
        });

        view.containers.container_stop_request.connect((container) => {
            try {

                repository.containers().stop(container);
                string message = "Container %s successfully stopped".printf(container.id);
                this.init_container_list();
                message_dispatcher.dispatch(Gtk.MessageType.INFO, message);

            } catch (Sdk.Docker.RequestError e) {
                message_dispatcher.dispatch(Gtk.MessageType.ERROR, (string) e.message);
            }
        });
        
        view.containers.container_kill_request.connect((container) => {

            try {
                repository.containers().kill(container);
                string message = "Container %s successfully killed".printf(container.id);
                this.init_container_list();
                message_dispatcher.dispatch(Gtk.MessageType.INFO, message);

            } catch (Sdk.Docker.RequestError e) {
                message_dispatcher.dispatch(Gtk.MessageType.ERROR, (string) e.message);
            }
        });
        
        view.containers.container_rename_request.connect((container, label) => {
            this.handle_container_rename(container, label);
        });
    }

    public void listen_headerbar() {

        view.headerbar.docker_daemon_lookup_request.connect((docker_path) => {

            try {

                this.repository = create_repository(docker_path);

                this.init_image_list();
                this.init_container_list();

                message_dispatcher.dispatch(Gtk.MessageType.INFO, "Connected to docker daemon");

            } catch (Sdk.Docker.RequestError e) {
                message_dispatcher.dispatch(Gtk.MessageType.ERROR, (string) e.message);
                this.view.images.init(null);
                this.view.containers.init(null);
            }
        });
    }

    protected void init_image_list() throws Sdk.Docker.RequestError {
        Sdk.Docker.Model.Image[]? images = null;
        try {
            images = repository.images().list();
        } catch (Sdk.Docker.RequestError e) {
            message_dispatcher.dispatch(Gtk.MessageType.ERROR, (string) e.message);
        } finally {
            this.view.images.init(images);
        }
    }

    protected void init_container_list() throws Sdk.Docker.RequestError {

        var container_collection = new Sdk.Docker.Model.Containers();

        foreach(Sdk.Docker.Model.ContainerStatus status in Sdk.Docker.Model.ContainerStatus.all()) {
            var containers = repository.containers().list(status);
            container_collection.add(status, containers);
        }

        this.view.containers.init(container_collection);
    }

    protected Sdk.Docker.Repository create_repository(string docker_path) {
        
        var client = new Sdk.Docker.UnixSocketClient(docker_path);
        
        client.response_success.connect((response) => {
            this.view.headerbar.connected_to_docker_daemon(true);
        });
        
        client.request_error.connect((response) => {
            this.view.headerbar.connected_to_docker_daemon(false);
        });
        
        return new Sdk.Docker.Repository(client);
    }
    
    
    protected void handle_container_rename(Sdk.Docker.Model.Container container, Gtk.Label label) {

        #if GTK_GTE_3_16
        var pop = new Gtk.Popover(label);
        pop.position = Gtk.PositionType.BOTTOM;

        var box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
        box.margin = 5;
        box.pack_start(new Gtk.Label("New name"), false, true, 5);

        var entry = new Gtk.Entry();
        entry.set_text(label.get_text());

        box.pack_end(entry, false, true, 5);

        pop.add(box);

        entry.activate.connect (() => {
            try {
                container.name = entry.text;

                repository.containers().rename(container);

                this.init_container_list();

            } catch (Sdk.Docker.RequestError e) {
                message_dispatcher.dispatch(Gtk.MessageType.ERROR, (string) e.message);
            }
        });

        pop.show_all();
        #endif
    }
}
