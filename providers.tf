terraform { 
  cloud { 
    
    organization = "027-spring-cld" 

    workspaces { 
      name = "my_single_workspace_using_terraform" 
    } 
  } 
  
required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}
provider "aws" {
  region = "us-east-1"
}