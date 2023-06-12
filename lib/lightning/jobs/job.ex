defmodule Lightning.Jobs.Job do
  @moduledoc """
  Ecto model for Jobs.

  A Job contains the fields for defining a job.

  * `body`
    The expression/javascript code
  * `name`
    A plain text identifier
  * `adaptor`
    An NPM style string that contains both the module name and it's version.
    E.g. `@openfn/language-http@v1.2.3` or `@openfn/language-foo@latest`.
    While the version suffix isn't enforced here as it's not strictly necessary
    in this context, the front end will ensure a version is stated (`@latest`
    being the default).
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Lightning.Credentials.Credential
  alias Lightning.Workflows.Workflow
  alias Lightning.Projects.{ProjectCredential}

  @type t :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: Ecto.UUID.t() | nil,
          body: String.t() | nil,
          enabled: boolean(),
          name: String.t() | nil,
          adaptor: String.t() | nil,
          credential: nil | Credential.t() | Ecto.Association.NotLoaded.t(),
          workflow: nil | Workflow.t() | Ecto.Association.NotLoaded.t()
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "jobs" do
    field :body, :string

    field :enabled, :boolean, default: true
    field :name, :string
    field :adaptor, :string, default: "@openfn/language-common@latest"

    belongs_to :project_credential, ProjectCredential
    has_one :credential, through: [:project_credential, :credential]
    belongs_to :workflow, Workflow
    has_one :project, through: [:workflow, :project]

    field :delete, :boolean, virtual: true

    timestamps()
  end

  def new(attrs \\ %{}) do
    change(%__MODULE__{}, attrs)
  end

  @doc false
  def changeset(job, attrs) do
    change =
      job
      |> cast(attrs, [
        :id,
        :name,
        :body,
        :enabled,
        :adaptor,
        :project_credential_id,
        :workflow_id
      ])

    change
    |> assoc_constraint(:workflow)
    |> validate_length(:name, max: 100)
    |> validate_format(:name, ~r/^[a-zA-Z0-9_\- ]*$/)
  end

  @doc """
  Attaches a workflow to a job, this is useful when you have an unpersisted
  Workflow changeset - and want it to be created at the same time as a Job.


  Example:

      workflow =
        Ecto.Changeset.cast(
          %Lightning.Workflows.Workflow{},
          %{ "project_id" => attrs[:project_id], "id" => Ecto.UUID.generate() },
          [:project_id, :id]
        )

      job =
        %Job{}
        |> Ecto.Changeset.change()
        |> Job.put_workflow(workflow)
        |> Job.changeset(attrs)

  """
  @spec put_workflow(
          Ecto.Changeset.t(__MODULE__.t()),
          Ecto.Changeset.t(Workflow.t())
        ) ::
          Ecto.Changeset.t(__MODULE__.t())
  def put_workflow(%Ecto.Changeset{} = changeset, %Ecto.Changeset{} = workflow) do
    changeset
    |> Ecto.Changeset.put_change(
      :workflow_id,
      workflow |> Ecto.Changeset.get_field(:id)
    )
    |> Ecto.Changeset.put_assoc(:workflow, workflow)
  end

  def put_project_credential(job, project_credential) do
    job
    |> Ecto.Changeset.put_assoc(:project_credential, project_credential)
  end
end
