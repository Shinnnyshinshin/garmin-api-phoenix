defmodule GarminPlannerWeb.WorkoutBuilderLive do
  use GarminPlannerWeb, :live_view

  alias GarminPlanner.Workouts
  alias GarminPlanner.Workouts.{Workout, YAMLParser}
  alias GarminPlanner.Accounts

  @default_yaml """
  name: "My Workout"
  description: ""
  tags: []

  steps:
    - type: warmup
      duration: 10min
      target: easy

    - type: interval
      duration: 20min
      target: tempo

    - type: cooldown
      duration: 10min
      target: easy
  """

  @impl true
  def mount(params, _session, socket) do
    {workout, yaml, title} = load_workout(params)
    parsed = parse_yaml(yaml)

    {:ok,
     socket
     |> assign(:page_title, title)
     |> assign(:workout, workout)
     |> assign(:yaml, yaml)
     |> assign(:parsed, parsed)
     |> assign(:saving, false)
     |> assign(:save_error, nil)
     |> assign(:users, Accounts.list_users())}
  end

  @impl true
  def handle_event("yaml_changed", %{"yaml" => yaml}, socket) do
    parsed = parse_yaml(yaml)
    {:noreply, assign(socket, yaml: yaml, parsed: parsed)}
  end

  @impl true
  def handle_event("save", %{"workout" => params}, socket) do
    yaml = socket.assigns.yaml

    case parse_yaml(yaml) do
      {:error, reason} ->
        {:noreply, assign(socket, save_error: reason)}

      {:ok, parsed_attrs} ->
        user_id = Map.get(params, "user_id") |> parse_int()
        steps_json = parsed_attrs.steps

        attrs = %{
          "name" => parsed_attrs.name,
          "description" => parsed_attrs.description,
          "tags" => parsed_attrs.tags,
          "steps" => steps_json,
          "user_id" => user_id,
          "sport_type" => "running"
        }

        case save_workout(socket.assigns.workout, attrs) do
          {:ok, _workout} ->
            {:noreply,
             socket
             |> put_flash(:info, "Workout saved.")
             |> push_navigate(to: ~p"/workouts")}

          {:error, changeset} ->
            errors =
              Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
                Enum.reduce(opts, msg, fn {key, value}, acc ->
                  String.replace(acc, "%{#{key}}", to_string(value))
                end)
              end)

            {:noreply, assign(socket, save_error: inspect(errors))}
        end
    end
  end

  defp load_workout(%{"id" => id}) do
    workout = Workouts.get_workout!(id)
    steps = Workout.decoded_steps(workout)
    yaml = build_yaml_from_workout(workout, steps)
    {workout, yaml, "Edit Workout"}
  end

  defp load_workout(_params) do
    {%Workout{}, String.trim(@default_yaml), "New Workout"}
  end

  defp parse_yaml(yaml) when is_binary(yaml) do
    case YAMLParser.parse(yaml) do
      {:ok, attrs} -> {:ok, attrs}
      {:error, reason} -> {:error, reason}
    end
  end

  defp build_yaml_from_workout(workout, steps) do
    tags =
      case workout.tags do
        nil -> "[]"
        t -> "[#{Enum.map_join(String.split(t, ","), ", ", &"\"#{String.trim(&1)}\"")}]"
      end

    steps_yaml = YAMLParser.steps_to_yaml(steps)

    """
    name: "#{workout.name}"
    description: "#{workout.description || ""}"
    tags: #{tags}

    #{steps_yaml}
    """
    |> String.trim()
  end

  defp save_workout(%Workout{id: nil}, attrs), do: Workouts.create_workout(attrs)
  defp save_workout(%Workout{} = w, attrs), do: Workouts.update_workout(w, attrs)

  defp parse_int(nil), do: nil
  defp parse_int(""), do: nil
  defp parse_int(s) when is_binary(s), do: elem(Integer.parse(s), 0)
  defp parse_int(i) when is_integer(i), do: i

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-7xl mx-auto">
      <div class="flex justify-between items-center mb-4">
        <h1 class="text-2xl font-bold"><%= @page_title %></h1>
        <.link href={~p"/workouts"} class="btn btn-ghost btn-sm">← Library</.link>
      </div>

      <.form for={%{}} phx-submit="save" class="mb-4 flex items-center gap-4">
        <div class="flex-1">
          <label class="label text-sm font-medium">Assign to user</label>
          <select name="workout[user_id]" class="select select-bordered w-full max-w-xs">
            <option value="">— no user —</option>
            <%= for user <- @users do %>
              <option value={user.id} selected={@workout.user_id == user.id}>
                <%= user.name %>
              </option>
            <% end %>
          </select>
        </div>
        <div class="pt-6">
          <.button type="submit" phx-disable-with="Saving…">Save Workout</.button>
        </div>
      </.form>

      <%= if @save_error do %>
        <div class="alert alert-error mb-4">
          <svg xmlns="http://www.w3.org/2000/svg" class="stroke-current shrink-0 h-6 w-6" fill="none" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10 14l2-2m0 0l2-2m-2 2l-2-2m2 2l2 2m7-2a9 9 0 11-18 0 9 9 0 0118 0z" />
          </svg>
          <span><%= @save_error %></span>
        </div>
      <% end %>

      <div class="grid grid-cols-2 gap-4 h-[calc(100vh-280px)]">
        <%!-- Left: YAML editor --%>
        <div class="flex flex-col">
          <label class="label font-medium">YAML Editor</label>
          <textarea
            id="yaml-editor"
            class="textarea textarea-bordered font-mono text-sm flex-1 resize-none leading-relaxed"
            phx-debounce="500"
            phx-change="yaml_changed"
            name="yaml"
            spellcheck="false"
          ><%= @yaml %></textarea>
        </div>

        <%!-- Right: Preview --%>
        <div class="flex flex-col overflow-auto">
          <label class="label font-medium">Preview</label>
          <div class="bg-base-200 rounded-lg p-4 flex-1 overflow-auto">
            <%= case @parsed do %>
              <% {:error, reason} -> %>
                <div class="alert alert-warning">
                  <span class="font-mono text-sm"><%= reason %></span>
                </div>
              <% {:ok, attrs} -> %>
                <div class="space-y-3">
                  <div>
                    <p class="font-bold text-lg"><%= attrs.name %></p>
                    <%= if attrs.description && attrs.description != "" do %>
                      <p class="text-sm text-base-content/60"><%= attrs.description %></p>
                    <% end %>
                  </div>
                  <.step_list steps={Jason.decode!(attrs.steps)} depth={0} />
                </div>
            <% end %>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp step_list(assigns) do
    ~H"""
    <div class={["space-y-1", @depth > 0 && "pl-4 border-l-2 border-base-300"]}>
      <%= for step <- @steps do %>
        <.step_card step={step} depth={@depth} />
      <% end %>
    </div>
    """
  end

  defp step_card(%{step: %{"type" => "repeat"}} = assigns) do
    ~H"""
    <div class="rounded p-2 bg-base-300/50">
      <div class="flex items-center gap-2 mb-1">
        <span class="badge badge-neutral badge-sm">repeat</span>
        <span class="text-sm font-medium"><%= @step["iterations"] %>×</span>
      </div>
      <.step_list steps={@step["steps"] || []} depth={@depth + 1} />
    </div>
    """
  end

  defp step_card(assigns) do
    ~H"""
    <div class="flex items-center gap-2 rounded p-2 bg-base-100">
      <span class={["badge badge-sm", step_badge_class(@step["type"])]}>
        <%= @step["type"] %>
      </span>
      <span class="text-sm flex-1">
        <%= format_duration(@step) %>
      </span>
      <%= if target = @step["target"] do %>
        <span class="badge badge-outline badge-sm font-mono">
          <%= format_target(target) %>
        </span>
      <% end %>
    </div>
    """
  end

  defp step_badge_class("warmup"), do: "badge-info"
  defp step_badge_class("cooldown"), do: "badge-info"
  defp step_badge_class("interval"), do: "badge-error"
  defp step_badge_class("recovery"), do: "badge-success"
  defp step_badge_class("rest"), do: "badge-ghost"
  defp step_badge_class(_), do: "badge-neutral"

  defp format_duration(%{"duration_type" => "time", "duration_value" => val}) when is_number(val) do
    secs = round(val)

    if rem(secs, 60) == 0,
      do: "#{div(secs, 60)} min",
      else: "#{secs} sec"
  end

  defp format_duration(%{
         "duration_type" => "distance",
         "duration_value" => val,
         "duration_unit" => unit
       }) do
    "#{val} #{unit}"
  end

  defp format_duration(_), do: "open"

  defp format_target(%{"type" => "zone", "zone_name" => name}), do: name
  defp format_target(%{"type" => "pace_range", "min_pace" => min, "max_pace" => max}), do: "#{min}–#{max}"
  defp format_target(_), do: "—"
end
