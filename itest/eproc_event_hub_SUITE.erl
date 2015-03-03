%/--------------------------------------------------------------------
%| Copyright 2013-2015 Erisata, UAB (Ltd.)
%|
%| Licensed under the Apache License, Version 2.0 (the "License");
%| you may not use this file except in compliance with the License.
%| You may obtain a copy of the License at
%|
%|     http://www.apache.org/licenses/LICENSE-2.0
%|
%| Unless required by applicable law or agreed to in writing, software
%| distributed under the License is distributed on an "AS IS" BASIS,
%| WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%| See the License for the specific language governing permissions and
%| limitations under the License.
%\--------------------------------------------------------------------

%%
%%  Testcases for `eproc_fsm`.
%%
-module(eproc_event_hub_SUITE).
-compile([{parse_transform, lager_transform}]).
-export([all/0, init_per_suite/1, end_per_suite/1]).
-export([
    test_cluster/1
]).
-include_lib("kernel/include/inet.hrl").
-include_lib("common_test/include/ct.hrl").
-include_lib("eproc_core/include/eproc.hrl").


%%
%%  CT API.
%%
all() -> [
    test_cluster
    ].


%%
%%  CT API, initialization.
%%
init_per_suite(Config) ->
    DataDir = proplists:get_value(data_dir, Config),
    %
    {ok, [SysConfig]} = file:consult(DataDir ++ "/sys.config"),
    lists:foreach(fun ({App, Envs}) ->
        application:load(App),
        [ application:set_env(App, N, V) || {N, V} <- Envs ]
    end, SysConfig),
    {ok, StartedApps} = application:ensure_all_started(lager, permanent),
    %
    lager:notice("Starting slave nodes..."),
    {ok, NodeA} = slave_start(testA, DataDir),
    {ok, NodeB} = slave_start(testB, DataDir),
    Nodes = [NodeA, NodeB],
    lager:notice("Starting slave nodes... done, nodes=~p", [Nodes]),
    receive after 1000 -> ok end,   % Wait for application, to become running.
    [{started_apps, StartedApps}, {started_nodes, Nodes} | Config].



%%
%%  CT API, cleanup.
%%
end_per_suite(Config) ->
    [ ok = application:stop(App) || App  <- proplists:get_value(started_apps,  Config)],
    [ ok = slave:stop(Node)      || Node <- proplists:get_value(started_nodes, Config)],
    ok.



%% =============================================================================
%%  Helpers.
%% =============================================================================

%%
%%
%%
this_host() ->
    {ok, ShortHostname} = inet:gethostname(),
    {ok, #hostent{h_name = FullHostname}} = inet:gethostbyname(ShortHostname),
    {ok, FullHostname}.


%%
%%
%%
slave_start(SlaveName, DataDir) ->
    SlaveNameStr = erlang:atom_to_list(SlaveName),
    {ok, ThisHost} = this_host(),
    % Check if node not started.
    pang = net_adm:ping(erlang:list_to_atom(SlaveNameStr ++ "@" ++ ThisHost)),
    % Prepare sys.config
    {ok, ConfigSrc} = file:read_file(DataDir ++ "/" ++ SlaveNameStr ++ ".config.src"),
    ConfigDst = re:replace(ConfigSrc, <<"{{HOSTNAME}}">>, erlang:list_to_binary(ThisHost), [global]),
    ok = file:write_file(DataDir ++ "/" ++ SlaveNameStr ++ ".config", ConfigDst),
    % Start node and required apps.
    SlaveArgs = "-config " ++ DataDir ++ "/" ++ SlaveNameStr,
    {ok, SlaveNode} = slave:start(ThisHost, SlaveName, SlaveArgs),
    true        = rpc:call(SlaveNode, code,        set_path,           [code:get_path()]),
    {ok, _Apps} = rpc:call(SlaveNode, application, ensure_all_started, [eproc_core, permanent]),
    {ok, SlaveNode}.



%% =============================================================================
%%  Testcases.
%% =============================================================================


%%
%%  Check, if HUB works in a cluster (notify is called in any of the nodes).
%%
test_cluster(Config) ->
    [NodeA, NodeB] = Nodes = proplists:get_value(started_nodes, Config),
    % Check, if applications were started.
    {[AppsA, AppsB], []} = rpc:multicall(Nodes, application, which_applications, []),
    true = lists:member(eproc_core, [ App || {App, _, _} <- AppsA ]),
    true = lists:member(eproc_core, [ App || {App, _, _} <- AppsB ]),
    % Check if hub works in a cluster.
    Name = eproc_event_hub_SUITE__test_cluster,
    {[{ok, PidA}, {ok, PidB}], []} = rpc:multicall(Nodes, eproc_event_hub, start, [{local, Name}]),
    true = erlang:link(PidA),
    true = erlang:link(PidB),
    {ok, SessionA1} = eproc_event_hub:listen({Name, NodeA}, 2000),
    {ok, SessionA2} = eproc_event_hub:listen({Name, NodeA}, 2000),
    {ok, SessionB1} = eproc_event_hub:listen({Name, NodeB}, 2000),
    {ok, SessionB2} = eproc_event_hub:listen({Name, NodeB}, 2000),
    ok = rpc:call(NodeA, eproc_event_hub, notify, [Name, eventA1]),
    ok = rpc:call(NodeB, eproc_event_hub, notify, [Name, eventA2]),
    ok = rpc:call(NodeA, eproc_event_hub, notify, [Name, eventB1]),
    ok = rpc:call(NodeB, eproc_event_hub, notify, [Name, eventB2]),
    receive after 100 -> ok end,
    {ok, eventA1} = rpc:call(NodeA, eproc_event_hub, recv, [Name, SessionA1, [{eventA1, [], ['$_']}]]),
    {ok, eventA2} = rpc:call(NodeA, eproc_event_hub, recv, [Name, SessionA2, [{eventA2, [], ['$_']}]]),
    {ok, eventB1} = rpc:call(NodeB, eproc_event_hub, recv, [Name, SessionB1, [{eventB1, [], ['$_']}]]),
    {ok, eventB2} = rpc:call(NodeB, eproc_event_hub, recv, [Name, SessionB2, [{eventB2, [], ['$_']}]]),
    ok.


