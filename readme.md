# Microsoft Entra ID Automation Samples

Welcome to the Microsoft Entra ID Automation Samples repository! This collection provides practical, real-world examples of how to manage and automate tasks in Microsoft Entra ID using scripts and Infrastructure as Code.

The goal of this repository is to offer clear, well-documented solutions for common administrative and operational scenarios, helping you leverage the power of automation for your identity management needs.

## Guiding Principles

Each sample in this repository is designed with the following principles in mind:

*   **Practicality**: Solves a real-world problem.
*   **Clarity**: Includes detailed explanations and clean, readable code.
*   **Flexibility**: Provides multiple implementation methods where applicable (e.g., Bash, PowerShell, Terraform).
*   **Security**: Follows best practices, such as using managed identities and adhering to the principle of least privilege.

## Available Samples

Below is a catalog of the available samples. Each sample resides in its own directory and includes a detailed `README.md` with specific instructions.

| Sample | Description | Technologies Used |
| :--- | :--- | :--- |
| **Granting Graph API Permissions to a Managed Identity** | Demonstrates how to grant Microsoft Graph API application permissions to a user-assigned managed identity. This is crucial for enabling Azure services to securely access Entra ID data without credentials. | `Terraform`, `Azure CLI`, `Bash`, `PowerShell` |
| *More samples coming soon...* | | |

## General Prerequisites

While each sample has its own specific requirements, most will require the following tools:

*   An active **Azure Subscription**.
*   **Azure CLI** for authentication and resource management.
*   Sufficient permissions in your Microsoft Entra ID tenant to manage resources (e.g., `Application Administrator` or `Cloud Application Administrator` roles).

## How to Use

1.  **Clone the repository**:
    ```sh
    git clone <repository-url>
    ```
2.  **Navigate to a sample directory**:
    ```sh
    cd name-of-sample-directory
    ```
3.  **Follow the instructions**: Each sample directory contains a dedicated `README.md` file with detailed, step-by-step instructions for that specific scenario.

## Contributing

We welcome contributions to this repository! If you have an idea for a new sample, a bug to report, or an improvement to an existing example, please follow these steps:

1.  **Open an Issue**: For bug reports or feature requests, please open an issue first to discuss the change you wish to make.
2.  **Fork and Create a Branch**: Fork the repository and create a new branch for your work.
3.  **Submit a Pull Request**: Once your changes are ready, submit a pull request with a clear description of the problem and solution.

## License

This project is licensed under the MIT License.
