

# Module eproc_archive #
* [Data Types](#types)
* [Function Index](#index)
* [Function Details](#functions)

__This module defines the `eproc_archive` behaviour.__
<br></br>
 Required callback functions: `archive_instance/4`, `archive_transitions/4`.

<a name="types"></a>

## Data Types ##




### <a name="type-ref">ref()</a> ###


__abstract datatype__: `ref()`

<a name="index"></a>

## Function Index ##


<table width="100%" border="1" cellspacing="0" cellpadding="2" summary="function index"><tr><td valign="top"><a href="#archive_instance-4">archive_instance/4</a></td><td></td></tr><tr><td valign="top"><a href="#archive_transitions-4">archive_transitions/4</a></td><td></td></tr><tr><td valign="top"><a href="#ref-2">ref/2</a></td><td></td></tr></table>


<a name="functions"></a>

## Function Details ##

<a name="archive_instance-4"></a>

### archive_instance/4 ###


<pre><code>
archive_instance(ArchiveRef::<a href="#type-archive_ref">archive_ref()</a>, Instance::#instance{}, Transitions::[#transition{}], Messages::[#message{}]) -&gt; ok
</code></pre>

<br></br>



<a name="archive_transitions-4"></a>

### archive_transitions/4 ###


<pre><code>
archive_transitions(ArchiveRef::<a href="#type-archive_ref">archive_ref()</a>, Instance::#instance{}, Transitions::[#transition{}], Messages::[#message{}]) -&gt; ok
</code></pre>

<br></br>



<a name="ref-2"></a>

### ref/2 ###


<pre><code>
ref(Module::module(), Args::term()) -&gt; {ok, <a href="#type-archive_ref">archive_ref()</a>}
</code></pre>

<br></br>



