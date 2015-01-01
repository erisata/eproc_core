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
%%  Interface for processes sending messages to FSMs.
%%  It is used by the `eproc_fsm` to resolve event source (sender),
%%  if not specified explicitly.
%%
%%  The event source should be in format `{Type, Identifier}`, where
%%  the Type identifies a class of the sender and the Identifier the
%%  corresponding instance.
%%
-module(eproc_event_src).
-export([set_source/1, source/0, remove/0]).
-include("eproc.hrl").


%% =============================================================================
%% API functions.
%% =============================================================================


%%
%%  Set message source description for this process.
%%
-spec set_source(Source :: event_src()) -> ok.

set_source(Source) ->
    erlang:put('eproc_event_src$source', Source),
    ok.


%%
%%  Get message source description of the current process.
%%
-spec source() -> Source :: event_src() | undefined.

source() ->
    erlang:get('eproc_event_src$source').


%%
%%  Remove the source description for this process.
%%
-spec remove() -> ok.

remove() ->
    erlang:erase('eproc_event_src$source'),
    ok.


