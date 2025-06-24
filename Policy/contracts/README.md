# Protection Shield Protocol

A simple smart contract for creating protection shields and processing damage claims on the Stacks blockchain.

## What it does

- Create protection shields with coverage limits
- Pay maintenance fees to keep shields active
- Submit damage claims for compensation
- Process claims (admin only)

## Quick Start

1. **Install Clarinet**
   ```bash
   npm install -g @hirosystems/clarinet-cli
   ```

2. **Check the contract**
   ```bash
   clarinet check
   ```

3. **Run tests**
   ```bash
   clarinet test
   ```

## Main Functions

### Create a Shield
```clarity
(contract-call? .protection-shield create-protection-shield u1000 u10 u1000)
;; Creates shield with 1000 STX coverage, 10 STX fee, 1000 blocks duration
```

### Submit a Claim
```clarity
(contract-call? .protection-shield submit-damage-claim u1 u500 "Equipment damaged")
;; Submit claim for shield #1, requesting 500 STX compensation
```

### Pay Maintenance Fee
```clarity
(contract-call? .protection-shield pay-maintenance-fee u1)
;; Pay fee for shield #1
```

## Error Codes

- `u100` - Not authorized
- `u102` - Shield not found
- `u104` - Shield expired
- `u105` - Invalid claim
- `u106` - Claim already processed

## License

MIT