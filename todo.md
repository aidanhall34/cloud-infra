
- Set up github authentication for Grafana
    - Do the Grafana side config
    - Create a script for doing the Github side configuration for a project called "homelab" (this directories name)
    - Ensure that Grafana secrets are handled securely in Github
    - Generate any required static tokens and place them into the ./secrets directory
    - Disable the default admin account
    - Configure a variables to put my account details into the SSO config
- Set up discord notifications
    - Set up a github action to send a message to discord upon completion of the job
    - It should report the task status, so it must always execute.
    - Ensure that the webhook URL and any other key material is handled as a secret
    - It should also include the time the entire job took, the start date of the pipeline, start time of the action job (the end of the run), and the total execution time (the delta of the 2 timestamps) 
- Configure a makefile to run the CI locally with act, the github actions task runner
    - act should be configured to accept a github token.
- Re-write all scripts into a makefile, and document within the makefile.
    - Include a list of all actions in the readme, link the line in the makefile to the action name in the README.md\
        so that it can be looked up directly from the readme.
- Create a docs file called "terraform.md", which explains the terraform layout and modules
    - ensure that each explanation links to the relevant file, and that when referencing a module, a link to the line number with the start of the module is added.
    - It should be remembered that this doc style should always be followed. If a bit of code or config is updated and functions change, update the reference in the documentation
- Setup automation for configuring mikrotik router
    - We should be able to automatically deploy wireguard and DNS configuration from the repo to the router locally.
    - At some point in the future, I may have a github actions runner locally, write the automation as a github action
        that I can run with act.\
        This action should not trigger when running in github actions.\
    - Write a make recipe to trigger the action
    - Authenticate to the mikrotik device over SSH
    - Make SSH keys be a file that is read into what ever program you use to connect to the router
