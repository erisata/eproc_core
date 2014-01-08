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
%%  TODO: Description.
%%
-module(eproc_router).
-behaviour(eproc_attribute).
-export([add_key/2]).
-export([started/1, created/3, updated/2, removed/1, store/3]).


%% =============================================================================
%%  Public API.
%% =============================================================================

%%
%%
%%
add_key(Key, Scope) ->
    eproc_attribute:action(?MODULE, undefined, {key, Key}, Scope).



%% =============================================================================
%%  Callbacks for `eproc_attribute`.
%% =============================================================================

%%
%%  FSM started.
%%
started(ActiveAttrs) ->
    {error, undefined}. % TODO


%%
%%  Attribute created.
%%
created(Name, {key, Key}, _Scope) ->
    {error, undefined}. % TODO


%%
%%  Attribute updated by user.
%%
updated(Attribute, {key, Key}) ->
    {error, undefined}. % TODO


%%
%%  Attribute removed by `eproc_fsm`.
%%
removed(_Attribute) ->
    {error, undefined}. % TODO


%%
%%  Store attribute information in the store.
%%  This callback is invoked in the context of `eproc_store`.
%%
store(Store, Attribute, Args) ->
    ok. % TODO


%% =============================================================================
%%  Internal functions.
%% =============================================================================

