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
%%  Supervises FSM instances. This is default implementation for
%%  the FSM supervisor, altrough registry implementations can have own.
%%
%%  This supervisor can work in two modes, altrough when started in
%%  particular mode, can only work in that mode.
%%
%%    * `default` mode uses `simple_one_for_one` supervisor;
%%    * `custom` mode uses `one_for_one` supervisor.
%%
-module(eproc_fsm_sup).
-behaviour(supervisor).
-compile([{parse_transform, lager_transform}]).
-export([start_link/2, start_fsm/4]).
-export([init/1]).
-include("eproc.hrl").

-type mode() :: default | custom.


%% =============================================================================
%%  Public API.
%% =============================================================================

%%
%%  Start this supervisor.
%%
-spec start_link(
        Name :: otp_name(),
        Mode :: mode()
    ) ->
        pid() | {error, term()} | term().

start_link(Name, Mode) ->
    supervisor:start_link(Name, ?MODULE, {Mode}).


%%
%%  Starts new `eproc_fsm` instance using the default `eproc_fsm:start_link/2` function.
%%
-spec start_fsm(
        Supervisor  :: otp_ref(),
        Mode        :: mode(),
        FsmRef      :: fsm_ref(),
        StartSpec   :: list() | {module(), atom(), list()}
    ) ->
        {ok, pid()}.

start_fsm(Supervisor, default, _FsmRef, StartLinkArgs) when is_list(StartLinkArgs) ->
    {ok, _Pid} = supervisor:start_child(Supervisor, StartLinkArgs);

start_fsm(Supervisor, custom, FsmRef, StartLinkMFA = {Module, _, _}) ->
    Spec = {FsmRef, StartLinkMFA, transient, 10000, worker, [eproc_fsm, Module]},
    {ok, _Pid} = supervisor:start_child(Supervisor, Spec).


%% =============================================================================
%%  Callbacks for `supervisor`.
%% =============================================================================

%%
%%  Supervisor configuration.
%%
init({default}) ->
    {ok, {{simple_one_for_one, 100, 10}, [
        {eproc_fsm, {eproc_fsm, start_link, []}, transient, 10000, worker, [eproc_fsm]}
    ]}};

init({custom}) ->
    {ok, {{one_for_one, 100, 10}, [
    ]}}.
