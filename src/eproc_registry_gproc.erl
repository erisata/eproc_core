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
%%  GProc based registry. This registry is not dedesigned to work
%%  in clusters. It can be used for tests or single node deploymens.
%%
-module(eproc_registry_gproc).
-behaviour(eproc_registry).
-behaviour(gen_server).
-compile([{parse_transform, lager_transform}]).
-export([start_link/0]).
-export([supervisor_child_specs/1, register_fsm/3]).
-export([register_name/2, unregister_name/1, whereis_name/1, send/2]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).
-include("eproc.hrl").

-define(BY_INST(I), {n, l, {eproc_inst, I}}).
-define(BY_NAME(N), {n, l, {eproc_name, N}}).
-define(BY_KEY(K),  {p, l, {eproc_key,  K}}).


%% =============================================================================
%%  Public API.
%% =============================================================================

%%
%%  Start the registry.
%%
start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, {}, []).



%% =============================================================================
%%  Callbacks for `eproc_registry`.
%% =============================================================================

%%
%%  Returns supervisor child specifications for starting the registry.
%%
supervisor_child_specs(_RegistryArgs) ->
    Spec = {?MODULE, {?MODULE, start_link, []}, permanent, 10000, worker, [?MODULE]},
    {ok, [Spec]}.


%%
%%  Registers FSM with its InstId.
%%
register_fsm(_RegistryArgs, _InstId, Refs) ->
    Register = fun (Ref) ->
        true = gproc:reg(gproc_key(Ref))
    end,
    ok = lists:foreach(Register, Refs).



%% =============================================================================
%%  Callbacks for OTP Process Registry.
%% =============================================================================

%%
%%  Process registration is not implemented for this registry.
%%
register_name(_Name, _Pid) ->
    erlang:error(not_implemented).


%%
%%  Process unregistration is not implemented for this registry.
%%
unregister_name(_Name) ->
    erlang:error(not_implemented).


%%
%%  Process ID lookup. This is used by generic behaviours.
%%
whereis_name({fsm, _RegistryArgs, FsmRef}) ->
    gproc:whereis_name(gproc_key(FsmRef));

whereis_name({new, _RegistryArgs, FsmRef, StartLinkMFA}) ->
    {ok, Pid} = start_fsm(FsmRef, StartLinkMFA),
    Pid.


%%
%%  Sends a message to the specified process.
%%
send(Pid, Message) when is_pid(Pid) ->
    Pid ! Message;

send({fsm, _RegistryArgs, FsmRef}, Message) ->
    gproc:send(gproc_key(FsmRef), Message);

send({new, _RegistryArgs, FsmRef, StartLinkMFA}, Message) ->
    {ok, Pid} = start_fsm(FsmRef, StartLinkMFA),
    Pid ! Message.



%% =============================================================================
%%  Internal state of the module.
%% =============================================================================

-record(state, {
}).



%% =============================================================================
%%  Callbacks for `gen_server`.
%% =============================================================================

%%
%%  Initialization.
%%
init({}) ->
    self() ! 'eproc_registry_gproc$load',
    {ok, #state{}}.


%%
%%  Syncronous calls.
%%
handle_call(_Message, _From, State) ->
    {stop, not_implemented, not_implemented, State}.


%%
%%  Asynchronous messages.
%%
handle_cast(_Message, State) ->
    {stop, not_implemented, State}.


%%
%%  Loads all FSM instances asynchronously.
%%
handle_info('eproc_registry_gproc$load', State) ->
    % TODO: Start loading all instances.
    {noreply, State}.



%%
%%  Invoked when terminating.
%%
terminate(_Reason, _State) ->
    ok.


%%
%%  Invoked in the case of code upgrade.
%%
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.



%% =============================================================================
%%  Internal functions.
%% =============================================================================


%%
%%  Converts FSM refs to gproc keys.
%%
gproc_key({inst, InstId}) ->
    ?BY_INST(InstId);

gproc_key({name, Name}) ->
    ?BY_NAME(Name).


%%
%%  Starts new FSM.
%%
start_fsm(FsmRef, StartLinkMFA) ->
    Pid = todo, % TODO
    {ok, Pid}.


