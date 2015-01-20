using Gtk;
using WebKit;
using Soup;

public class OHSC: Window {

    private const string TITLE = "OHSC";
    private const string HOME_URL = "https://google.at";
    private const string DEFAULT_PROTOCOL = "https";
    private const string USER = "smith@darkboxed.org";

    private string host;
    private uint16 port;

    private Regex protocol_regex;

    private Entry url_bar;
    private WebView web_view;
    private ToolButton back_button;
    private ToolButton forward_button;
    private ToolButton reload_button;
    private ToolButton login_button;
    private ToggleToolButton register_button;

    public OHSC(string host, uint16 port) {
        this.host = host;
        this.port = port;

        this.title = OHSC.TITLE;
        set_default_size(800, 600);

        try {
            this.protocol_regex = new Regex(".*://.*");
        } catch (RegexError e) {
            critical("%s", e.message);
        }

        create_widgets();
        connect_signals();
        this.url_bar.grab_focus();
    }

    private void create_widgets() {
        var toolbar = new Toolbar();
        this.back_button = new ToolButton.from_stock(Stock.GO_BACK);
        this.forward_button = new ToolButton.from_stock(Stock.GO_FORWARD);
        this.reload_button = new ToolButton.from_stock(Stock.REFRESH);
        this.login_button =
            new ToolButton.from_stock(Stock.DIALOG_AUTHENTICATION);
        login_button.label = "Log in";
        this.register_button = new ToggleToolButton.from_stock(Stock.NEW);
        register_button.label = "Register";
        toolbar.add(this.back_button);
        toolbar.add(this.forward_button);
        toolbar.add(this.reload_button);
        toolbar.add(new SeparatorToolItem());
        toolbar.add(this.login_button);
        toolbar.add(this.register_button);

        this.url_bar = new Entry();

        this.web_view = new WebView();
        // for inspector
        this.web_view.settings.enable_developer_extras = true;

        var scrolled_window = new ScrolledWindow(null, null);
        scrolled_window.set_policy(PolicyType.AUTOMATIC, PolicyType.AUTOMATIC);
        scrolled_window.add(this.web_view);

        var vbox = new VBox(false, 0);
        vbox.pack_start(toolbar, false, true, 0);
        vbox.pack_start(this.url_bar, false, true, 0);
        vbox.add(scrolled_window);
        add(vbox);
    }

    private void connect_signals() {
        this.destroy.connect(Gtk.main_quit);
        this.url_bar.activate.connect(on_activate);
        this.web_view.title_changed.connect((source, frame, title) => {
                this.title = "%s - %s".printf(title, OHSC.TITLE);
            });
        this.web_view.load_committed.connect((source, frame) => {
                this.url_bar.text = frame.get_uri();
                update_buttons();
            });
        this.back_button.clicked.connect(this.web_view.go_back);
        this.forward_button.clicked.connect(this.web_view.go_forward);
        this.reload_button.clicked.connect(this.web_view.reload);

        this.register_button.clicked.connect(this.toggle_register);
        this.login_button.clicked.connect(this.do_login);

        this.web_view.web_inspector.inspect_web_view.connect((_i, _v) => {
            var win = new Window();
            var scr = new ScrolledWindow(null, null);
            WebView *view = new WebView();
            scr.add(view);
            scr.set_policy(PolicyType.AUTOMATIC, PolicyType.AUTOMATIC);
            win.add(scr);
            win.show_all();
            return view;
        });
    }

    private void update_buttons() {
        this.back_button.sensitive = this.web_view.can_go_back();
        this.forward_button.sensitive = this.web_view.can_go_forward();
    }

    private void toggle_register() {
        var doc = this.web_view.get_dom_document();

        // HACK: cleaner way to keep this object alive than messing with
        // refcounts manually???
        RegisterData reg =
            new RegisterData(doc, this.host, this.port, this);

        if (this.register_button.active) {
            activate_register(reg);
        } else {
            deactivate_register(reg);
        }
    }

    private string user_agent {
        get { return this.web_view.settings.get_user_agent(); }
    }

    private static void activate_register(RegisterData reg) {
        // frames?
        reg.doc.add_event_listener("click", (GLib.Callback)handle_register,
                false, reg.ref());
    }
    private static void deactivate_register(RegisterData reg) {
        reg.doc.remove_event_listener("click", (GLib.Callback)handle_register,
                false);
    }

    private static Json.Array get_path(DOMNode? node) {
        var path = new Json.Array();

        do {
            var parent = node.parent_node;
            var o = new Json.Object();

            if (node is DOMElement) {
                var elem = node as DOMElement;

                var id = elem.get_attribute("id");
                if (id != "") {
                    o.set_string_member("lnId", id);
                } else {
                    o.set_null_member("lnId");
                }

                var classes = new Json.Array();
                foreach (var cls in elem.get_attribute("class").split(" ")) {
                    classes.add_string_element(cls);
                }
                o.set_array_member("lnClasses", classes);

                o.set_string_member("lnTag", elem.tag_name);
            }

            if (parent != null) {
                var siblings = parent.child_nodes;
                for (int i = 0; i < siblings.length; ++i) {
                    if (siblings.item(i) == node) {
                        o.set_int_member("lnOffset", i);
                    }
                }
            }

            path.add_object_element(o);
            node = parent;
        } while (node != null);

        return path;
    }

    private static CookieJar get_cookie_jar() {
        var sess = WebKit.get_default_session();
        return sess.get_feature(typeof(Soup.CookieJar)) as Soup.CookieJar;
    }

    private static Json.Array get_cookies(string url) {
        var jar = get_cookie_jar();
        var arr = new Json.Array();
        foreach (var ck in jar.get_cookie_list(new Soup.URI(url), true)) {
            arr.add_string_element(ck.to_cookie_header());
        }
        return arr;
    }

    private static bool
    handle_register(DOMDOMWindow w, DOMEvent? ev0, RegisterData reg) {
        var ev = ev0 as DOMMouseEvent;
        if (ev != null) {
            DOMNode? node = reg.doc.element_from_point(ev.x, ev.y);

            var path = get_path(node);
            var cookies = get_cookies(reg.doc.url);

            var res = new Json.Object();
            res.set_string_member("tag", "Register");
            res.set_string_member("regURL", reg.doc.url);
            res.set_array_member("regFormLocator", path);
            res.set_array_member("regCookies", cookies);

            make_request_async.begin(res, reg.host, reg.port, (obj, res) => {
                Json.Object resp = null;
                try {
                    resp = make_request_async.end(res);
                } catch (Error e) {
                    // FIXME
                    error_dialog(reg.this_, e);
                    return;
                }

                switch (resp.get_string_member("tag")) {
                case "CommandSuccess":
                    // FIXME?
                    var old_icon = reg.this_.register_button.stock_id;
                    reg.this_.register_button.stock_id = Stock.YES;
                    GLib.Timeout.add(2000, () => {
                        reg.this_.register_button.stock_id = old_icon;
                        reg.this_.register_button.sensitive = false;
                        return false;
                    });
                    break;
                case "CommandFail":
                    // FIXME XXX ADSKNASLDKNA
                    command_fail(reg.this_,
                            resp.get_string_member("failReason"));
                    break;
                }
            });
        }

        reg.unref();

        return false; // continue with other handlers
    }

    private void do_login() {
        var login = new Json.Object();
        login.set_string_member("tag", "Login");
        login.set_string_member("loginUserId", USER);
        login.set_string_member("loginURL", this.web_view.uri);
        login.set_string_member("loginUserAgent", this.user_agent);

        make_request_async.begin(login, host, port, (obj, res) => {
            Json.Object resp = null;
            try {
                resp = make_request_async.end(res);
            } catch (Error e) {
                error_dialog(this, e);
                return;
            }

            switch (resp.get_string_member("tag")) {
            case "LoginSuccess":
                login_success(resp);
                break;
            case "CommandFail":
                // FIXME XXX ADSKNASLDKNA
                command_fail(this, resp.get_string_member("failReason"));
                break;
            }
        });
    }

    private static void command_fail(Window parent, string reason) {
        var msg =
            new MessageDialog(
                parent,
                DialogFlags.DESTROY_WITH_PARENT,
                MessageType.ERROR,
                ButtonsType.OK,
                "Registration failed for some reason:\n\n%s",
                reason);
        msg.response.connect((_) => msg.destroy());
        msg.run();
    }

    private static void error_dialog(Window parent, Error e) {
        var msg =
            new MessageDialog(
                parent,
                DialogFlags.DESTROY_WITH_PARENT,
                MessageType.ERROR,
                ButtonsType.OK,
                "Could not reach the server:\n\n%s",
                e.message);
        msg.response.connect((_) => msg.destroy());
        msg.run();
    }

    private void login_success(Json.Object resp) {
        var cookies = resp.get_array_member("cookies");
        string? redirect = resp.get_string_member("targetURL");

        var jar = get_cookie_jar();

        for (uint i = 0; i < cookies.get_length(); ++i) {
            var ch = cookies.get_string_element(i);
            var c = Cookie.parse(ch, null);

            if(c == null) {
                print("Cannot parse cookie: " + ch + "\n");
            } else {
                print("Cookie : " + c.domain + "\n");
                jar.add_cookie(c);
            }
        }

        if (redirect != null) {
            this.web_view.load_uri(redirect);
        } else {
            this.web_view.reload();
        }
    }

    private static async Json.Object
    make_request_async(Json.Object data, string host, uint16 port)
    throws Error {
        var client = new SocketClient();
        client.tls = false;
        var js = new Json.Node.alloc().init_object(data);
        var g = new Json.Generator();
        g.set_root(js);
        var r = Resolver.get_default();
        var ip = yield r.lookup_by_name_async(host);
        var addr = new InetSocketAddress(ip.nth_data(0), port);
        var conn = yield client.connect_async(addr);
        yield conn.output_stream.write_async(g.to_data(null).data);
        var parser = new Json.Parser();
        yield parser.load_from_stream_async(conn.input_stream);
        yield conn.close_async();
        return parser.get_root().get_object();
    }

    private void on_activate() {
        var url = this.url_bar.text;
        if (!this.protocol_regex.match(url)) {
            url = "%s://%s".printf(OHSC.DEFAULT_PROTOCOL, url);
        }
        this.web_view.open(url);
    }

    public void start() {
        get_cookie_jar().accept_policy = CookieJarAcceptPolicy.ALWAYS;
        var session = WebKit.get_default_session();
        session.ssl_use_system_ca_file = true; // THIS IS NOT THE DEFAULT!!!


        show_all();
        this.web_view.open(OHSC.HOME_URL);
    }

    public static int main(string[] args) {
        Gtk.init(ref args);

        if (args.length != 3) {
            print("usage: ohsc SERVER_HOST SERVER_PORT\n");
            return 1;
        }

        var browser = new OHSC(args[1], (uint16) int.parse(args[2]));
        browser.start();

        Gtk.main();

        return 0;
    }

    class RegisterData: GLib.Object {
        public DOMDocument doc;
        public string host;
        public uint16 port;
        public OHSC this_;
        public RegisterData(DOMDocument doc, string host, uint16 port,
                            OHSC this_) {
            this.doc = doc;
            this.host = host;
            this.port = port;
            this.this_ = this_;
        }
    }
}

// vim: set sw=4:
