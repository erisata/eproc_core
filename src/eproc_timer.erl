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
-module(eproc_timer).
-behaviour(eproc_attribute).
-export([set/4, set/3, set/2, cancel/1]).
-export([started/1, created/3, updated/2, removed/1, store/3]).


-record(timer, {
    delay,
    event
}).

%% =============================================================================
%%  Public API.
%% =============================================================================

%%
%%
%%
set(Name, After, Event, Scope) ->
    %% TODO: Register sent message.
    eproc_attribute:action(?MODULE, Name, {timer, After, Event}, Scope).


%%
%%
%%
set(After, Event, Scope) ->
    %% TODO: Register sent message.
    eproc_attribute:action(?MODULE, undefined, {timer, After, Event}, Scope).


%%
%%
%%
set(After, Event) ->
    %% TODO: Register sent message.
    eproc_attribute:action(?MODULE, undefined, {timer, After, Event}, next).


%%
%%
%%
cancel(Name) ->
    eproc_attribute:set(?MODULE, Name, {timer, remove}).



%% =============================================================================
%%  Callbacks for `eproc_attribute`.
%% =============================================================================

%%
%%  FSM started.
%%
started(ActiveAttrs) ->
    {error, undefined}.


%%
%%  Attribute created.
%%
created(Name, {timer, After, Event}, _Scope) ->
    {error, undefined}; % TODO

created(Name, {timer, remove}, _Scope) ->
    {error, {unknown_timer, Name}}.


%%
%%  Attribute updated by user.
%%
updated(Attribute, {timer, After, Event}) ->
    {error, undefined};

updated(Attribute, {timer, remove}) ->
    {error, undefined}.


%%
%%  Attribute removed by `eproc_fsm`.
%%
removed(Attribute) ->
    {error, undefined}.


%%
%%  Store attribute information in the store.
%%  This callback is invoked in the context of `eproc_store`.
%%
store(Store, Attribute, Args) ->
    ok. % TODO



%% =============================================================================
%%  Internal functions.
%% =============================================================================

