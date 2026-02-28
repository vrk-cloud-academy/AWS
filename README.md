# 🚀 EC2 Auto Launch via MobaXterm (AWS CLI)

This project allows you to automatically:

- Launch a new EC2 instance
- Create a key pair (if not exists)
- Wait for instance readiness
- Auto SSH into the instance
- Clean up instances easily

All using **MobaXterm + AWS CLI**.

---

## 📌 Requirements

- Windows with MobaXterm
- AWS CLI installed
- AWS credentials configured (`aws configure`)
- Default VPC present

---

## 📂 Project Files

| File | Purpose |
|------|---------|
| create-ec2.sh | Launch and SSH into EC2 |
| cleanup.sh | Terminate EC2 instances |

---

## 🛠 How It Works (Stages)

### Stage 1 – Fetch Latest AMI
Uses AWS SSM to dynamically get latest Amazon Linux 2 AMI.

### Stage 2 – Key Pair Check
Creates `minikube` key if not available.

### Stage 3 – Launch Instance
Uses:
- t3.micro
- Default VPC
- Auto public IP
- Name format: `Instance_DDMM`

### Stage 4 – Wait Until Running
Uses AWS wait command.

### Stage 5 – SSH Connection
- Auto-add host key
- Disable X11
- Direct login into instance

---

## ▶️ Usage

Make executable:

```bash
chmod +x create-ec2.sh
