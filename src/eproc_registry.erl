%/--------------------------------------------------------------------
%| Copyright 2013-2014 Erisata, UAB (Ltd.)
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
%%  Interface module for a registry. The registry is responsible for:
%%
%%   1. Supervising running FSMs.   TODO: Is registry a correct place for the FSM supervisor?
%%   2. Locating FSMs by an instance id, a name or a key.
%%   3. Await for specific FSM.
%%   4. Send message to a FSM.
%%
%%  TODO: Implement the `supervisor` behaviour, so this module can be used `{via, ...}`.
%%
%%    * `register_name/2`
%%    * `unregister_name/1`
%%    * `send/2`
%%
%%
-module(eproc_registry).
-compile([{parse_transform, lager_transform}]).
-export([ref/0, ref/2]).
-export([
    start_instance/3, await/3,
    register_inst/2, register_name/3, register_keys/3,
    send_event/3,
    make_new_fsm_ref/3, make_fsm_ref/2
]).
-export([
    register_name/2, unregister_name/1, send/2
]).
-export_type([ref/0]).
-include("eproc.hrl").

-opaque ref() :: {Callback :: module(), Args :: term()}.


%% =============================================================================
%%  Callback definitions.
%% =============================================================================


%%
%%
%%
-callback start_link(
        RegistryArgs    :: term()
    ) ->
        {ok, pid()} |
        {error, term()} |
        ignore.


%%
%%
%%
-callback start_instance(
        RegistryArgs    :: term(),
        InstId          :: inst_id(),
        StartOpts       :: term()
    ) ->
    ok.


%%
%%
%%
-callback await(
        RegistryArgs    :: term(),
        FsmRef          :: fsm_ref(),
        Timeout         :: integer()
    ) ->
    ok | {error, timeout}.


%%
%%
%%
-callback register_inst(
        RegistryArgs    :: term(),
        InstId          :: inst_id()
    ) ->
    ok.


%%
%%
%%
-callback register_name(
        RegistryArgs    :: term(),
        InstId          :: inst_id(),
        Name            :: term()
    ) ->
    ok.


%%
%%
%%
-callback register_keys(
        RegistryArgs    :: term(),
        InstId          :: inst_id(),
        Keys            :: [term()]
    ) ->
    ok.


%%
%%
%%
-callback send_event(
        RegistryArgs    :: term(),
        FsmRef          :: fsm_ref(),
        Message         :: term()
    ) ->
    ok.



%% =============================================================================
%%  Public API.
%% =============================================================================


%%
%%  Returns the default registry reference.
%%
-spec ref() -> {ok, registry_ref()} | undefined.

ref() ->
    case eproc_core_app:registry_cfg() of
        {ok, {RegistryMod, RegistryArgs}} ->
            ref(RegistryMod, RegistryArgs);
        undefined ->
            undefined
    end.


%%
%%  Create a registry reference.
%%
-spec ref(module(), term()) -> {ok, registry_ref()}.

ref(Module, Args) ->
    {ok, {Module, Args}}.


%%
%%
%%
start_instance(Registry, InstId, StartOpts) ->
    {ok, {RegistryMod, RegistryArgs}} = resolve_ref(Registry),
    RegistryMod:start_instance(RegistryArgs, InstId, StartOpts).


%%
%%
%%
await(Registry, FsmRef, Timeout) ->
    {ok, {RegistryMod, RegistryArgs}} = resolve_ref(Registry),
    RegistryMod:await(RegistryArgs, FsmRef, Timeout).


%%
%%
%%
register_inst(Registry, InstId) ->
    {ok, {RegistryMod, RegistryArgs}} = resolve_ref(Registry),
    RegistryMod:register_inst(RegistryArgs, InstId).


%%
%%
%%
register_name(_Registry, _InstId, undefined) ->
    ok;

register_name(Registry, InstId, Name) ->
    {ok, {RegistryMod, RegistryArgs}} = resolve_ref(Registry),
    RegistryMod:register_name(RegistryArgs, InstId, Name).


%%
%%
%%
register_keys(_Registry, _InstId, []) ->
    ok;

register_keys(Registry, InstId, Keys) when is_list(Keys) ->
    {ok, {RegistryMod, RegistryArgs}} = resolve_ref(Registry),
    RegistryMod:register_keys(RegistryArgs, InstId, Keys).


%%
%%
%%
send_event(Registry, FsmRef, Message) ->
    {ok, {RegistryMod, RegistryArgs}} = resolve_ref(Registry),
    RegistryMod:send_event(RegistryArgs, FsmRef, Message).


%%
%%  Creates a reference that points to a process, that should be started
%%  prior to sending a message to it. The reference can be passed to any
%%  process as a registry reference (uses `{via, Mudule, Name}`).
%%  I.e. you can use it as:
%%
%%      {ok, Ref} = eproc_registry:make_new_fsm_ref(Registry, FsmRef, StartLinkMFA),
%%      Response = gen_server:call(Ref, Message).
%%
%%  Here registry is a reference obtained using `eproc_registry:ref/1-2`,
%%  FsmRef is an FSM reference, usually returned from the `eproc_fsm:create/3`
%%  and StartLinkMFA is `{Module, Function, Args}` used to start and link
%%  the FSM.
%%
-spec make_new_fsm_ref(
        Registry        :: registry_ref(),
        FsmRef          :: fsm_ref(),
        StartLinkMFA    :: {FsmModule :: module(), FsmStartFunction :: atom(), FsmStartArgs :: list()}
    ) ->
        {ok, Ref}
    when
        Ref :: {via,
            RegistryModule :: module(),
            {new, RegistryArgs :: term(), FsmRef :: fsm_ref(), StartLinkMFA :: tuple()}
        }.

make_new_fsm_ref(Registry, FsmRef, StartLinkMFA) ->
    {ok, {RegistryMod, RegistryArgs}} = resolve_ref(Registry),
    {ok, {via, RegistryMod, {new, RegistryArgs, FsmRef, StartLinkMFA}}}.


%%
%%  Creates a reference that points to an already started FSM.
%%  The reference is in `{via, Mudule, Name}` form so it can
%%  be passed to any process as an OTP process name.
%%
%%  This function is similar to `make_new_fsm_ref/3` except it refers
%%  to an already started process. The later reference a process
%%  that should be started before using it.
%%
-spec make_fsm_ref(
        Registry        :: registry_ref(),
        FsmRef          :: fsm_ref()
    ) ->
        {ok, Ref}
    when
        Ref :: {via,
            RegistryModule :: module(),
            {fsm, RegistryArgs :: term(), FsmRef :: fsm_ref()}
        }.
make_fsm_ref(Registry, FsmRef) ->
    {ok, {RegistryMod, RegistryArgs}} = resolve_ref(Registry),
    {ok, {via, RegistryMod, {fsm, RegistryArgs, FsmRef}}}.



%% =============================================================================
%%  Callbacks for `supervisor`.
%% =============================================================================
%%
%%  TODO: Should they be implemented by the target module?
%%

%%
%%  TODO: Implement.
%%
register_name(Name, Pid) ->
    no.


%%
%%  TODO: Implement.
%%
unregister_name(Name) ->
    ok.


%%
%%  TODO: Implement.
%%
send(Name, Message) ->
    Pid = undefined,
    Pid.


%% =============================================================================
%%  Internal functions.
%% =============================================================================


%%
%%  Resolve the provided (optional) registry reference.
%%
resolve_ref({RegistryMod, RegistryArgs}) ->
    {ok, {RegistryMod, RegistryArgs}};

resolve_ref(undefined) ->
    ref().


