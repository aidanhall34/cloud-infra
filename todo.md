I have added 2 new environments to the github repository.

1) build
2) deploy

Deploy is used for tf-apply commands, or any commands that touch production systems.\
Build is used for building artifacts (containers, images with packer).\
Anything that needs access to a linode token MUST be run in a Github environment.
Configure the following actions:\
molecule-gateway - No env\
unit-tests - No env\
pre-commit - No env\
packer build - build\
terraform plan - build\
terraform apply - deploy\

Before a PR can be merged to main, all "No env" jobs must pass.
Packer build should be run when a change is found in the ansible or packer directories.\
Terraform plan should be run when packer runs or when a change is detected in the terraform directory.\
Before the deploy environment can be run, all jobs must be successful in the build environment.\
Deploy can only be run from the main branch\

The no-env job should still run on dev branches.\
The molecule job should still be manually triggered by required.
