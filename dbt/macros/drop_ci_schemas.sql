{#- Called at the end of a CI run: dbt run-operation drop_ci_schemas -#}
{% macro drop_ci_schemas() %}
    {% if target.name != 'ci' %}
        {{ exceptions.raise_compiler_error("drop_ci_schemas only runs on the ci target") }}
    {% endif %}
    {% for suffix in ['', '_staging', '_intermediate', '_marts', '_dbt_test__audit'] %}
        {% do run_query("drop schema if exists " ~ target.database ~ "." ~ target.schema ~ suffix ~ " cascade") %}
    {% endfor %}
{% endmacro %}
