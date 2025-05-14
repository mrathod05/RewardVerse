aptos move publish \
--profile admin \


aptos multisig create \
--additional-owners  0x974cb7225bb8b12ec93e7f78940175681fa9d5930f27061018ab0eb89337d59b\
--num-signatures-required 2 \
--profile admin \
--assume-yes

aptos move view \
--function-id 0x1::multisig_account::num_signatures_required \
--args address:"$multisig_addr" \
--profile admin

aptos move view \
--function-id 0x1::multisig_account::owners \
--args address:"$multisig_addr" \
--profile admin

aptos move view \
--function-id 0x1::multisig_account::last_resolved_sequence_number \
--args address:"$multisig_addr" \
--profile admin

aptos move view \
--function-id 0x1::multisig_account::next_sequence_number \
--args address:"$multisig_addr" \
--profile admin

aptos multisig create-transaction \
--multisig-address $multisig_addr \
--json-file ./payloads/add_user.json \
--profile admin

aptos move view \
--function-id 0x1::multisig_account::get_pending_transactions \
--args address:"$multisig_addr" \
--profile admin

aptos move view \
--function-id 0x1::multisig_account::can_be_executed \
--args \
address:"$multisig_addr" \
u64:1 \
--profile admin

aptos multisig verify-proposal \
--multisig-address $multisig_addr \
--json-file ./payloads/add_user.json \
--sequence-number 1 \
--profile admin

aptos multisig approve \
--multisig-address $multisig_addr \
--sequence-number 1 \
--profile admin

aptos multisig execute \
--multisig-address $multisig_addr \
--profile admin2