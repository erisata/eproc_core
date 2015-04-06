

# Module eproc_registry #
* [Data Types](#types)
* [Function Index](#index)
* [Function Details](#functions)

__This module defines the `eproc_registry` behaviour.__
<br></br>
 Required callback functions: `supervisor_child_specs/1`, `register_fsm/3`, `register_name/2`, `unregister_name/1`, `whereis_name/1`, `send/2`.

<a name="types"></a>

## Data Types ##




### <a name="type-ref">ref()</a> ###


__abstract datatype__: `ref()`




### <a name="type-registry_fsm_ref">registry_fsm_ref()</a> ###


__abstract datatype__: `registry_fsm_ref()`

<a name="index"></a>

## Function Index ##


<table width="100%" border="1" cellspacing="0" cellpadding="2" summary="function index"><tr><td valign="top"><a href="#make_fsm_ref-2">make_fsm_ref/2</a></td><td></td></tr><tr><td valign="top"><a href="#make_new_fsm_ref-3">make_new_fsm_ref/3</a></td><td></td></tr><tr><td valign="top"><a href="#ref-0">ref/0</a></td><td></td></tr><tr><td valign="top"><a href="#ref-2">ref/2</a></td><td></td></tr><tr><td valign="top"><a href="#register_fsm-3">register_fsm/3</a></td><td></td></tr><tr><td valign="top"><a href="#supervisor_child_specs-1">supervisor_child_specs/1</a></td><td></td></tr><tr><td valign="top"><a href="#whereis_fsm-2">whereis_fsm/2</a></td><td></td></tr></table>


<a name="functions"></a>

## Function Details ##

<a name="make_fsm_ref-2"></a>

### make_fsm_ref/2 ###


<pre><code>
make_fsm_ref(Registry::<a href="#type-registry_ref">registry_ref()</a>, FsmRef::<a href="#type-fsm_ref">fsm_ref()</a>) -&gt; {ok, Ref}
</code></pre>

<ul class="definitions"><li><code>Ref = {via, RegistryModule::module(), RegistryFsmRef::<a href="#type-registry_fsm_ref">registry_fsm_ref()</a>}</code></li></ul>


<a name="make_new_fsm_ref-3"></a>

### make_new_fsm_ref/3 ###


<pre><code>
make_new_fsm_ref(Registry::<a href="#type-registry_ref">registry_ref()</a>, FsmRef::<a href="#type-fsm_ref">fsm_ref()</a>, StartSpec::<a href="#type-fsm_start_spec">fsm_start_spec()</a>) -&gt; {ok, Ref}
</code></pre>

<ul class="definitions"><li><code>Ref = {via, RegistryModule::module(), RegistryFsmRef::<a href="#type-registry_fsm_ref">registry_fsm_ref()</a>}</code></li></ul>


<a name="ref-0"></a>

### ref/0 ###


<pre><code>
ref() -&gt; {ok, <a href="#type-registry_ref">registry_ref()</a>} | undefined
</code></pre>

<br></br>



<a name="ref-2"></a>

### ref/2 ###


<pre><code>
ref(Module::module(), Args::term()) -&gt; {ok, <a href="#type-registry_ref">registry_ref()</a>}
</code></pre>

<br></br>



<a name="register_fsm-3"></a>

### register_fsm/3 ###


<pre><code>
register_fsm(Registry::<a href="#type-registry_ref">registry_ref()</a>, InstId::<a href="#type-inst_id">inst_id()</a>, Refs::[<a href="#type-fsm_ref">fsm_ref()</a>]) -&gt; ok
</code></pre>

<br></br>



<a name="supervisor_child_specs-1"></a>

### supervisor_child_specs/1 ###


<pre><code>
supervisor_child_specs(Registry::<a href="#type-registry_ref">registry_ref()</a>) -&gt; {ok, list()}
</code></pre>

<br></br>



<a name="whereis_fsm-2"></a>

### whereis_fsm/2 ###


<pre><code>
whereis_fsm(Registry::<a href="#type-registry_ref">registry_ref()</a>, FsmRef::<a href="#type-fsm_ref">fsm_ref()</a>) -&gt; Pid::pid() | undefined
</code></pre>

<br></br>



