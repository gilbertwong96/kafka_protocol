-module(kpro_test_lib).

-export([ get_endpoints/1
        , guess_protocol/1
        ]).

-export([ get_topic/0
        ]).

-export([ sasl_config/0
        , sasl_config/1
        ]).

-export([ ssl_options/0
        ]).

-export([ with_connection/1
        , with_connection/2
        , with_connection/3
        , with_connection/4
        ]).

-type conn() :: kpro_connection:connection().
-type config() :: kpro_connection:config().

get_endpoints(Protocol) ->
  case osenv("KPRO_TEST_KAFKA_ENDPOINTS") of
    undefined -> default_endpoints(Protocol);
    Str -> kpro:parse_endpoints(Protocol, Str)
  end.

get_topic() ->
  case osenv("KPRO_TEST_KAFKA_TOPIC_NAME") of
    undefined -> <<"test-topic">>;
    Str -> iolist_to_binary(Str)
  end.

sasl_config() ->
  {plain, F} = sasl_config(file),
  {ok, Lines0} = file:read_file(F),
  Lines = binary:split(Lines0, <<"\n">>, [global]),
  [User, Pass] = lists:filter(fun(Line) -> Line =/= <<>> end, Lines),
  {plain, User, Pass}.

sasl_config(file) ->
  case osenv("KPRO_TEST_KAFKA_SASL_PLAIN_USER_PASS_FILE") of
    undefined ->
      F = "/tmp/kpro-test-sasl-plain-user-pass",
      ok = file:write_file(F, "alice\necila\n"),
      {plain, F};
    File ->
      {plain, File}
  end.

-spec with_connection(fun((conn()) -> any())) -> any().
with_connection(WithConnFun) ->
  with_connection(fun kpro:connect_any/2, WithConnFun).

-spec with_connection(fun(([kpro:endpoint()], config()) -> {ok, conn()}),
                      fun((conn()) -> any())) -> any().
with_connection(ConnectFun, WithConnFun) ->
  with_connection(_Config = #{}, ConnectFun, WithConnFun).

with_connection(Config, ConnectFun, WithConnFun) ->
  Endpoints = get_endpoints(guess_protocol(Config)),
  with_connection(Endpoints, Config, ConnectFun, WithConnFun).

with_connection(Endpoints, Config, ConnectFun, WithConnFun) ->
  {ok, Pid} = ConnectFun(Endpoints, Config),
  with_connection_pid(Pid, WithConnFun).

ssl_options() ->
  case osenv("KPRO_TEST_SSL_TRUE") of
    "TRUE" -> true;
    "true" -> true;
    "1" -> true;
    _ ->
      case osenv("KPRO_TEST_SSL_CA_CERT_FILE") of
        undefined ->
          default_ssl_options();
        CaCertFile ->
          [ {cacertfile, CaCertFile}
          , {keyfile,    osenv("KPRO_TEST_SSL_KEY_FILE")}
          , {certfile,   osenv("KPRO_TEST_SSL_CERT_FILE")}
          ]
      end
  end.

%%%_* Internal functions =======================================================

default_ssl_options() ->
  PrivDir = code:priv_dir(?APPLICATION),
  Fname = fun(Name) -> filename:join([PrivDir, ssl, Name]) end,
  [ {cacertfile, Fname("ca.crt")}
  , {keyfile,    Fname("client.key")}
  , {certfile,   Fname("client.crt")}
  ].

osenv(Name) ->
  case os:getenv(Name) of
    "" -> undefined;
    false -> undefined;
    Val -> Val
  end.

%% Guess protocol name from connection config.
guess_protocol(#{sasl := _}) -> sasl_ssl; %% we only test sasl on ssl
guess_protocol(#{ssl := false}) -> plaintext;
guess_protocol(#{ssl := _}) -> ssl;
guess_protocol(_) -> plaintext.

default_endpoints(plaintext) -> [{"localhost", 9092}];
default_endpoints(ssl) -> [{"localhost", 9093}];
default_endpoints(sasl_ssl) -> [{"localhost", 9094}].

with_connection_pid(Pid, Fun) ->
  try
    Fun(Pid)
  after
    unlink(Pid),
    kpro_connection:stop(Pid)
  end.

%%%_* Emacs ====================================================================
%%% Local Variables:
%%% allout-layout: t
%%% erlang-indent-level: 2
%%% End:
