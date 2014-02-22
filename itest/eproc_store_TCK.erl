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
%%  Testcases that should be valid for all the `eproc_store` implementations.
%%  See `eproc_store_ets_SUITE` for an example of using it.
%%
-module(eproc_store_TCK).
-export([all/0]).
-export([test_single_instance/1]).
-include_lib("common_test/include/ct.hrl").
-include("eproc.hrl").


%%
%%
%%
all() ->
    [test_single_instance].

%%
%%
%%
store(Config) ->
    proplists:get_value(store, Config).



%% =============================================================================
%%  Testcases.
%% =============================================================================

%%
%%  TODO: Check if the following scenario works:
%%
%%    * get and non-existing instance.
%%    * Add instance.
%%    * Add Another instance with name.
%%    * Add Another instance with same name.
%%    * Get instance.
%%    * Load instance.
%%    * Suspend.
%%    * Resume.
%%    * Add transition.
%%    * Add transition.
%%    * Suspend.
%%    * Resume.
%%    * Suspend.
%%    * Resume.
%%    * Suspend.
%%
test_single_instance(Config) ->
    {ok, InstId} = eproc_store:add_instance(store(Config), #instance{
        id = anything,
        group = new
    }),
    true = is_integer(InstId),
    ok.


