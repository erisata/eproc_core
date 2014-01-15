%/--------------------------------------------------------------------
%| Copyright 2013-2014 Erisata, Ltd.
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
%%  This module can be used in callback modules for the `eproc_fsm`
%%  to manage timers associated with the FSM.
%%
-module(eproc_fsm_attr__void).
-behaviour(eproc_fsm_attr).
-export([init/1, created/3, updated/2, removed/1]).
-include("eproc.hrl").

%%
%%  Persistent state.
%%
-record(data, {
    some
}).



%% =============================================================================
%%  Public API.
%% =============================================================================



%% =============================================================================
%%  Callbacks for `eproc_fsm_attr`.
%% =============================================================================

%%
%%  FSM started.
%%
init(ActiveAttrs) ->
    Started = [ {A, undefined} || A <- ActiveAttrs ],
    {ok, Started}.


%%
%%  Attribute created.
%%
created(Name, Action, _Scope) ->
    {error, undefined}.


%%
%%  Attribute updated by user.
%%
updated(Attribute, Action) ->
    {error, undefined}.


%%
%%  Attribute removed by `eproc_fsm`.
%%
removed(Attribute) ->
    {error, undefined}. % TODO



%% =============================================================================
%%  Internal functions.
%% =============================================================================

