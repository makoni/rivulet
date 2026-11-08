# Parity harness report

Rules the run applied:
- flags_are_the_same_on_both_sides
- run_names_the_pinned_reference_version
- inputs_are_the_same_on_both_sides
- request_sequence_is_the_same_on_both_sides
- recorded_classes_are_exercised_by_the_corpus
- entry_set_is_the_feed_and_hash_pair
- counts_match_the_rows_they_report
- state_and_starred_match_for_matched_entries
- parse_results_match_and_clock_values_are_not_compared
- payload_ids_read_through_the_map
- shape_rules_read_as_the_reference_writes_them
- self_is_each_side_own_configured_base_url
- statuses_match_except_where_a_recorded_row_covers_them
- order_compared_only_through_the_recorded_collation_row
- response_headers_read_with_the_first_value_winning
- media_proxy_is_off_on_the_reference_side
- names_are_ascii_so_the_auth_read_is_one_rule_on_both_sides
- report_names_every_rule_and_what_the_run_cannot_show

Classes the run read:
- foster_parenting: accepted
- name_classes: accepted
- zone_offset: accepted
- sub_second_cut: accepted
- collation_order: accepted
- method_mismatch: accepted
- trailing_slash: accepted
- repeated_header_value: fixed
- positions_and_counts: accepted
- bracketed_host: accepted
- media_proxy: accepted
- error_wording: accepted

What the run cannot show:
- that the run ran at all, because it is on demand and not in CI
- that the two sides read the same bytes over the network, because each fetch is its own hop
- the row order a storage read answers for rows sharing one value, which SQL does not fix
- the clock fields, which each side wrote at its own write instant
- the rules the stage-3 corpora already pin, which the run re-reads rather than pins
