import streamlit as st
import pandas as pd

from utils.helpers import run_query, exec_query, format_score

st.title("Dashboard")

df = run_query("""
    SELECT *
    FROM CLAID_TEST.RUN_SUMMARY
    ORDER BY RUN_TIMESTAMP DESC
""")

if df.empty:
    st.warning("No runs yet")
    st.stop()

df["PASS_RATE"] = df["PASS_RATE"].apply(format_score)
df["RUN_TIMESTAMP"] = pd.to_datetime(df["RUN_TIMESTAMP"])

last30 = df[df["RUN_TIMESTAMP"] >= (pd.Timestamp.now() - pd.Timedelta(days=30))]

st.subheader("Pass Rate Trend (Last 30 Days)")
st.line_chart(last30.set_index("RUN_TIMESTAMP")["PASS_RATE"])

latest = df.sort_values("RUN_TIMESTAMP").groupby("PROJECT_NAME").tail(1)

def status(p):
    return "🟢 Excellent" if p >= 90 else "🟡 Good" if p >= 70 else "🔴 Poor"

latest["STATUS"] = latest["PASS_RATE"].apply(status)

st.subheader("Latest Status")
st.dataframe(latest)

st.subheader("Quick Test Run")

projects_list = latest["PROJECT_NAME"].unique().tolist()

selected_project = st.selectbox(
    "Select Project",
    projects_list
)

if st.button("Run Now"):
    exec_query(f"""
        CALL CLAID_TEST.SP_RUN_TESTS(
            '{selected_project}',
            'MANUAL'
        )
    """)

    st.success(f"Triggered run for {selected_project}")
