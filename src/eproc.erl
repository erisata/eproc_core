%/--------------------------------------------------------------------
%| Copyright 2013 Karolis Petrauskas
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
%%  Main `eproc` API.
%%
-module(eproc).
-compile([{parse_transform, lager_transform}]).
-export([now/0, registry/0, store/0]).
-include("eproc.hrl").

-define(APP, eproc_core).

%%
%%  Returns current time, consistelly for the entire system.
%%
-spec now() -> datetime().

now() ->
    calendar:universal_time().


%%
%%  Returns a registry reference.
%%
-spec registry() -> registry_ref().

registry() ->
    {ok, {RegistryMod, RegistryArgs}} = application:get_env(?APP, registry),
    {ok, RegistryRef} = eproc_registry:ref(RegistryMod, RegistryArgs),
    RegistryRef.


%%
%%  Returns a store reference.
%%
-spec store() -> store_ref().

store() ->
    {ok, {StoreMod, StoreArgs}} = application:get_env(?APP, store),
    {ok, StoreRef} = eproc_store:ref(StoreMod, StoreArgs),
    StoreRef.


