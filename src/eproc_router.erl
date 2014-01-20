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
%%  Message router is used to map incoming messages to FSM events and
%%  to route them to the corresponding FSM instances.
%%
%%  An FSM whos messages should be routed using this router, should
%%  provide keys, that uniquelly identified an FSM instance. Function
%%  `add_key/2` should be used by FSM implementations to attach keys.
%%  Keys are maintained as FSM attributes and can be limited to
%%  particular scope.
%%
-module(eproc_router).
-behaviour(eproc_fsm_attr).
-export([add_key/2]).
-export([init/1, handle_created/3, handle_updated/4, handle_removed/2, handle_event/3]).
-include("eproc.hrl").


-record(data, {
    key :: term()
}).


%% =============================================================================
%%  Public API.
%% =============================================================================

%%
%%
%%
add_key(Key, Scope) ->
    Name = undefined,
    Action = {key, Key},
    eproc_fsm_attr:action(?MODULE, Name, Action, Scope).



%% =============================================================================
%%  Callbacks for `eproc_fsm_attr`.
%% =============================================================================

%%
%%  FSM started.
%%
init(ActiveAttrs) ->
    {ok, [ {A, undefined} || A <- ActiveAttrs ]}.


%%
%%  Attribute created.
%%
handle_created(_Attribute, {key, Key}, _Scope) ->
    AttrData = #data{key = Key},
    AttrState = undefined,
    {create, AttrData, AttrState}.


%%
%%  Keys cannot be updated.
%%
handle_updated(_Attribute, _AttrState, {key, _Key}, _Scope) ->
    {error, keys_non_updateable}.


%%
%%  Attributes should never be removed.
%%
handle_removed(_Attribute, _AttrState) ->
    ok.


%%
%%  Events are not used for keywords.
%%
handle_event(_Attribute, _AttrState, Event) ->
    throw({unknown_event, Event}).



%% =============================================================================
%%  Internal functions.
%% =============================================================================


