# Sub/Dom Interaction Runbook

This runbook documents the relationship-contract interaction layer under `/api/interactions`.

## 1. Contract Lifecycle

1. Dom creates a contract:

```http
POST /api/interactions/contracts
```

Body:

```json
{
  "sub_id": "<uuid>",
  "device_id": "<uuid-or-null>",
  "capabilities": ["lock_device", "message_sub", "restrict_packages"]
}
```

2. Dom activates contract:

```http
POST /api/interactions/contracts/{contract_id}/activate
```

3. Pause/revoke/archive when needed:

- `POST /api/interactions/contracts/{contract_id}/pause`
- `POST /api/interactions/contracts/{contract_id}/revoke`
- `POST /api/interactions/contracts/{contract_id}/archive`

## 2. Capability Governance

Update allowed command capabilities:

```http
PUT /api/interactions/contracts/{contract_id}/capabilities
```

Commands are rejected unless they are present in `capabilities` and contract state is `active`.

## 3. Command Flow

Issue command:

```http
POST /api/interactions/contracts/{contract_id}/commands
```

Body:

```json
{
  "command_type": "lock_device",
  "payload": {"source": "dom_dashboard"},
  "requires_sub_ack": true,
  "execute_after_seconds": 0,
  "expires_after_seconds": 1800
}
```

Destructive command types (`lock_device`, `restrict_packages`, `revoke_authority`, `wipe_data`) are created in `pending_confirmation` and must be confirmed:

```http
POST /api/interactions/commands/{command_id}/confirm
```

Sub acknowledges/rejects:

```http
POST /api/interactions/commands/{command_id}/ack
```

Body:

```json
{
  "accepted": true,
  "reason": "Acknowledged"
}
```

## 4. Safety Stops

Sub triggers emergency safe mode:

```http
POST /api/interactions/contracts/{contract_id}/safe-mode
```

Body:

```json
{
  "reason": "Overwhelmed",
  "duration_minutes": 30
}
```

While safe mode is active, new dom commands are blocked.

## 5. Transparency Endpoints

- Active constraints for both parties:
  - `GET /api/interactions/contracts/{contract_id}/active-constraints`
- Receipts / non-repudiation timeline:
  - `GET /api/interactions/contracts/{contract_id}/receipts`

## 6. Throttling Controls

Configured in environment variables:

- `INTERACTION_COOLDOWN_SECONDS` (default `45`)
- `INTERACTION_RATE_LIMIT_PER_WINDOW` (default `10`)
- `INTERACTION_RATE_WINDOW_SECONDS` (default `300`)

## 7. Audit Trail

Critical interaction actions are recorded in `audit_logs` with explicit `action`, `target_type`, and metadata.

## 8. Flutter Client Integration

`flutter_app/lib/core/services/dom_sub_interaction_service.dart` provides typed calls for:

- Contract lifecycle
- Capabilities update
- Command issue/confirm/ack
- Safe mode trigger
- Receipts and active-constraints queries
