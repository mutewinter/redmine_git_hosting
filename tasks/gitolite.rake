namespace :gitolite do
	desc "update gitolite repositories"
	task :update_repositories => [:environment] do
		projects = Project.active
		puts "Updating repositories for projects #{projects.join(' ')}"
		GitHosting.update_repositories(projects, false)
	end
	desc "fetch commits from gitolite repositories"
	task :fetch_changes => [:environment] do
		Repository.fetch_changesets
	end

  # Usage: rake gitolite:import_projects[user,parent]
	desc "Import and create projects from git repositories. Arguments [user login, parent project identifier]"
	task :import_projects, [:user, :parent] => :environment do |t, args|
    username = args.user
    parent_project_identifier = args.parent

    if username and username != 'nil'
      if user = User.find_by_login(username)
        puts "Found #{user} with login #{username}."
      else
        puts "User #{username} not found, aborting."
        exit
      end
    else
      puts "No user specified, imported projects will have no members."
    end

    if parent_project_identifier
      if parent_project = Project.find_by_identifier(parent_project_identifier)
        puts "Creating projects under parent project #{parent_project}."
      else
        puts "Parent project identifer #{parent_project_identifier} not found, aborting."
        exit
      end
    else
      puts "No parent specified, creating projects at top level"
    end

    git_repos_to_import = Dir.glob('import_git_projects/*')
    git_repos_to_import.each do |repo_folder_path|
      if File.directory? repo_folder_path
        repo_name = File.basename repo_folder_path
        puts "Processing #{repo_name}"

        # Remove periods from repository name for ChiliProject
        fixed_repo_name = repo_name.gsub('.', '_')

        new_repo_path = "/srv/git/repositories/#{parent_project_identifier ? "#{parent_project_identifier}/" : ""}#{fixed_repo_name}.git"

        if File.directory? new_repo_path
          puts "Repository #{new_repo_path} already exists, skipping import."
          next
        end

        clone_bare_repo(repo_folder_path, new_repo_path)

        puts "Creating project #{repo_name}"
        project = Project.create(
          :name => repo_name,
          :description => "Automatically created from CVS repository #{repo_name}",
          :identifier => fixed_repo_name,
          :is_public => true
        )

        # Assign the parent project if specified
        if parent_project
          puts "Assigning parent #{parent_project}"
          project.set_parent!(parent_project)
        end

        puts "Creating repository for project"
        # Add the Git repository
        repo = Repository::Git.create(
          :project_id => project.id,
          :url => new_repo_path
        )
        repo = GitRepositoryExtra.new()
        repo.extra = e
        repo.save

        # Add the user as a manager of the new project
        if user
          puts "Adding #{user} as project manager"

          membership = Member.new(
            :principal => user,
            :project_id => project.id,
            :role_ids => [3]
          )
          membership.save
        end # if user

      end # if File.directory?
    end # git_repos_to_import.each
  end # task :import_projects

	desc "Clone repos"
	task :clone_repos, [:parent] => :environment do |t, args|
    git_repos_to_import = Dir.glob('import_git_projects/*')
    git_repos_to_import.each do |repo_folder_path|
      if File.directory? repo_folder_path
        repo_name = File.basename repo_folder_path
        puts "Processing #{repo_name}"

        # Remove periods from repository name for ChiliProject
        fixed_repo_name = repo_name.gsub('.', '_')
        new_repo_path = "/srv/git/repositories/#{args.parent ? "#{args.parent}/" : ""}#{fixed_repo_name}.git"

        if existing_project = Project.find_by_identifier(fixed_repo_name)
          # Clear the repository cache for the existing project if it exists
          GitHosting::clear_cache_for_project(existing_project)
        end

        clone_bare_repo(repo_folder_path, new_repo_path)
      end
    end
  end

end

def clone_bare_repo(repo_directory, repo_destination)
  if File.exists? repo_destination
    puts "#{repo_destination} already exists, skipping clone."
  else
    puts "Cloning #{repo_directory} to #{repo_destination}"

    # Clone the existing repo into a bare repo in the repositories
    # folder
    command = "#{GitHosting.git_exec} clone --bare #{Dir.pwd}/#{repo_directory} #{repo_destination}" 
    puts command
    puts %x[#{command}]
  end

end
